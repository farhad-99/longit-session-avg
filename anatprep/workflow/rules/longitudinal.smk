"""
Longitudinal within-subject workflow rules:
  - trim_and_center: clip intensities and re-centre image origin
  - build_subject_template: build unbiased average template across sessions
  - register_sessions_to_template: rigidly register each session to the template
  - all_within_subject: terminal rule collecting all outputs
"""


# ── helpers ──────────────────────────────────────────────────────────────────


def get_trimmed_sessions(wildcards):
    """Return all trimmed images for a given subject and modality."""
    sessions = get_sessions(wildcards.subject)
    return [
        os.path.join(
            output_dir,
            f"sub-{wildcards.subject}",
            f"ses-{ses}",
            "anat",
            f"sub-{wildcards.subject}_ses-{ses}_{wildcards.modality}_desc-trimmed_anat.nii.gz",
        )
        for ses in sessions
    ]


def _all_templates():
    return [
        os.path.join(
            output_dir,
            f"sub-{sub}",
            "anat",
            f"sub-{sub}_{mod}_desc-subjectTemplate_anat.nii.gz",
        )
        for sub in subjects
        for mod in modalities
    ]


def _all_coregistered():
    return [
        os.path.join(
            output_dir,
            f"sub-{sub}",
            f"ses-{ses}",
            "anat",
            f"sub-{sub}_ses-{ses}_{mod}_space-subjectTemplate_desc-coregistered_anat.nii.gz",
        )
        for sub in subjects
        for ses in get_sessions(sub)
        for mod in modalities
    ]


# ── rules ─────────────────────────────────────────────────────────────────────


rule trim_and_center:
    """Clip hot/cold voxels and re-centre the image origin to intensity-weighted COM."""
    input:
        nii=os.path.join(
            bids_dir,
            "sub-{subject}",
            "ses-{session}",
            "anat",
            "sub-{subject}_ses-{session}_{modality}.nii.gz",
        ),
    output:
        nii=os.path.join(
            output_dir,
            "sub-{subject}",
            "ses-{session}",
            "anat",
            "sub-{subject}_ses-{session}_{modality}_desc-trimmed_anat.nii.gz",
        ),
    threads: 1
    resources:
        mem_mb=2000,
        runtime=15,
    log:
        os.path.join("logs", "trim_and_center", "{subject}_{session}_{modality}.log"),
    run:
        import logging
        import nibabel as nib
        import numpy as np

        logging.basicConfig(filename=log[0], level=logging.INFO)
        log_msg = logging.info

        log_msg(f"Loading {input.nii}")
        img = nib.load(input.nii)
        data = img.get_fdata(dtype=np.float32)
        affine = img.affine.copy()

        fg = data > 0
        if fg.sum() == 0:
            raise ValueError(f"No foreground voxels found in {input.nii}")

        fg_vals = data[fg]
        p10, p90 = np.percentile(fg_vals, [10, 90])
        log_msg(f"Clipping intensities to [{p10:.2f}, {p90:.2f}]")
        data = np.clip(data, p10, p90)
        # re-zero background after clipping
        data[~fg] = 0.0

        # intensity-weighted centre of mass in voxel space then world space
        weights = data.copy()
        weights[~fg] = 0.0
        total_weight = weights.sum()
        coords = np.indices(data.shape).astype(np.float32)
        com_vox = np.array(
            [(coords[i] * weights).sum() / total_weight for i in range(3)]
        )
        com_world = affine[:3, :3] @ com_vox + affine[:3, 3]
        log_msg(f"COM world coords: {com_world}")

        affine[:3, 3] = -com_world
        os.makedirs(os.path.dirname(output.nii), exist_ok=True)
        out_img = nib.Nifti1Image(data, affine, img.header)
        nib.save(out_img, output.nii)
        log_msg(f"Saved trimmed image to {output.nii}")


rule build_subject_template:
    """Build an unbiased subject template from all trimmed longitudinal sessions."""
    input:
        trimmed=get_trimmed_sessions,
    output:
        template=os.path.join(
            output_dir,
            "sub-{subject}",
            "anat",
            "sub-{subject}_{modality}_desc-subjectTemplate_anat.nii.gz",
        ),
    threads: 4
    resources:
        mem_mb=8000,
        runtime=120,
    log:
        os.path.join("logs", "build_subject_template", "{subject}_{modality}.log"),
    run:
        import logging
        import shutil
        import tempfile
        import ants

        logging.basicConfig(filename=log[0], level=logging.INFO)
        log_msg = logging.info

        log_msg(f"Building template for sub-{wildcards.subject} {wildcards.modality}")
        log_msg(f"Input images: {input.trimmed}")

        image_list = [ants.image_read(f) for f in input.trimmed]

        with tempfile.TemporaryDirectory() as tmpdir:
            template = ants.build_template(
                image_list=image_list,
                iterations=3,
                gradient_step=0.2,
                blending_weight=0.75,
                verbose=True,
                outprefix=os.path.join(tmpdir, "template_"),
            )

        os.makedirs(os.path.dirname(output.template), exist_ok=True)
        ants.image_write(template, output.template)
        log_msg(f"Saved subject template to {output.template}")


rule register_sessions_to_template:
    """Rigidly register each trimmed session image to the subject template."""
    input:
        moving=os.path.join(
            output_dir,
            "sub-{subject}",
            "ses-{session}",
            "anat",
            "sub-{subject}_ses-{session}_{modality}_desc-trimmed_anat.nii.gz",
        ),
        fixed=os.path.join(
            output_dir,
            "sub-{subject}",
            "anat",
            "sub-{subject}_{modality}_desc-subjectTemplate_anat.nii.gz",
        ),
    output:
        xfm=os.path.join(
            output_dir,
            "sub-{subject}",
            "ses-{session}",
            "xfm",
            "sub-{subject}_ses-{session}_{modality}_from-session_to-subjectTemplate_0GenericAffine.mat",
        ),
        warped=os.path.join(
            output_dir,
            "sub-{subject}",
            "ses-{session}",
            "anat",
            "sub-{subject}_ses-{session}_{modality}_space-subjectTemplate_desc-coregistered_anat.nii.gz",
        ),
    threads: 1
    resources:
        mem_mb=4000,
        runtime=30,
    log:
        os.path.join(
            "logs",
            "register_sessions_to_template",
            "{subject}_{session}_{modality}.log",
        ),
    run:
        import logging
        import shutil
        import ants

        logging.basicConfig(filename=log[0], level=logging.INFO)
        log_msg = logging.info

        log_msg(f"Registering {input.moving} -> {input.fixed}")

        fixed = ants.image_read(input.fixed)
        moving = ants.image_read(input.moving)

        result = ants.registration(
            fixed=fixed,
            moving=moving,
            type_of_transform="Rigid",
            verbose=False,
        )

        os.makedirs(os.path.dirname(output.xfm), exist_ok=True)
        os.makedirs(os.path.dirname(output.warped), exist_ok=True)

        # ANTs rigid registration produces a single affine .mat
        shutil.copy(result["fwdtransforms"][0], output.xfm)
        ants.image_write(result["warpedmovout"], output.warped)
        log_msg(f"Transform saved to {output.xfm}")
        log_msg(f"Warped image saved to {output.warped}")


rule all_within_subject:
    """Collect all subject templates and coregistered session images."""
    input:
        templates=_all_templates(),
        coregistered=_all_coregistered(),
