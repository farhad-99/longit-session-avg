"""
Rule: register_sessions_to_template

Per subject, per session, per modality:
  - Register the trimmed session image to the subject template rigidly,
    using the ANTs command-line tools (antsRegistrationSyNQuick.sh) rather
    than the ANTsPy python bindings, so the step runs as a multithreaded
    ITK binary instead of a python process
  - Save the rigid transform (.mat)
  - Save the warped image produced directly by registration (desc-warped)
  - Resample the moving image into template space with antsApplyTransforms
    to produce the final coregistered image (desc-coregistered)
"""


rule register_sessions_to_template:
    """Rigidly register each trimmed session image to the subject template."""
    input:
        moving=lambda wildcards: trimmed_path(wildcards.subject, wildcards.session, wildcards.modality),
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
            "sub-{subject}_ses-{session}_{modality}_space-subjectTemplate_desc-warped_anat.nii.gz",
        ),
        coregistered=os.path.join(
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
    shell:
        r"""
        set -euo pipefail
        exec > {log} 2>&1

        export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS={threads}

        mkdir -p "$(dirname {output.xfm})" "$(dirname {output.warped})"

        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        prefix="$tmpdir/reg_"

        echo "Registering {input.moving} -> {input.fixed}"
        antsRegistrationSyNQuick.sh -d 3 -t r \
            -f {input.fixed} -m {input.moving} \
            -o "$prefix" -n {threads}

        mv "${{prefix}}0GenericAffine.mat" {output.xfm}
        mv "${{prefix}}Warped.nii.gz" {output.warped}
        echo "Transform saved to {output.xfm}"
        echo "Warped image saved to {output.warped}"

        echo "Resampling {input.moving} into template space via antsApplyTransforms"
        antsApplyTransforms -d 3 \
            -i {input.moving} -r {input.fixed} \
            -t {output.xfm} \
            -n Linear \
            -o {output.coregistered}
        echo "Coregistered image saved to {output.coregistered}"
        """
