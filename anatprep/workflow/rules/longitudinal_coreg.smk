"""
Rule: register_sessions_to_template

Per subject, per session, per modality:
  - Register the trimmed session image to the subject template using ANTsPy
    rigid registration (type_of_transform="Rigid")
  - Save the rigid transform (.mat) and the warped session image
"""


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
    threads: workflow.cores
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
        import os
        import shutil

        os.environ["ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS"] = str(threads)
        import ants

        logger = logging.getLogger(
            f"register_sessions_to_template.{wildcards.subject}.{wildcards.session}.{wildcards.modality}"
        )
        logger.setLevel(logging.INFO)
        logger.handlers = [logging.FileHandler(log[0])]
        log_msg = logger.info

        log_msg(f"Registering {input.moving} -> {input.fixed}")

        try:
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
        except Exception:
            logger.exception("register_sessions_to_template failed")
            raise
