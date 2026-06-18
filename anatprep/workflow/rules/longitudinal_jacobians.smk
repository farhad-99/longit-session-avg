"""
Rule: compute_session_deformation

Per subject, per session, per modality — after the subject template exists:
  - Register the trimmed session to the subject template with SyN
    (deformable, not just rigid) to capture longitudinal change
  - Save the forward deformation field (y*.nii.gz, as in SPM longit)
  - Compute the Jacobian determinant of that deformation field
    (j*.nii.gz, as in SPM longit) — encodes local volumetric change
    relative to the midpoint template

These outputs mirror SPM12's spm.tools.longit.series outputs:
  avg_*.nii  → sub-{subject}_{modality}_desc-subjectTemplate_anat.nii.gz
  y*.nii     → ..._from-session_to-subjectTemplate_desc-warp_anat.nii.gz
  j*.nii     → ..._space-subjectTemplate_desc-jacobian_anat.nii.gz
"""


rule compute_session_deformation:
    """SyN-register each trimmed session to its subject template; compute Jacobian."""
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
        warp=os.path.join(
            output_dir,
            "sub-{subject}",
            "ses-{session}",
            "xfm",
            "sub-{subject}_ses-{session}_{modality}_from-session_to-subjectTemplate_desc-warp_anat.nii.gz",
        ),
        jacobian=os.path.join(
            output_dir,
            "sub-{subject}",
            "ses-{session}",
            "anat",
            "sub-{subject}_ses-{session}_{modality}_space-subjectTemplate_desc-jacobian_anat.nii.gz",
        ),
    threads: workflow.cores
    resources:
        mem_mb=12000,
        runtime=60,
    log:
        os.path.join(
            "logs",
            "compute_session_deformation",
            "{subject}_{session}_{modality}.log",
        ),
    run:
        import logging
        import os
        import subprocess
        import shutil
        import tempfile

        os.environ["ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS"] = str(threads)
        import ants

        logger = logging.getLogger(
            f"compute_session_deformation.{wildcards.subject}.{wildcards.session}.{wildcards.modality}"
        )
        logger.setLevel(logging.INFO)
        logger.handlers = [logging.FileHandler(log[0])]
        log_msg = logger.info

        try:
            log_msg(f"SyN registration: {input.moving} -> {input.fixed}")

            fixed = ants.image_read(input.fixed)
            moving = ants.image_read(input.moving)

            # SyNRA: rigid + affine initialisation followed by SyN deformable
            result = ants.registration(
                fixed=fixed,
                moving=moving,
                type_of_transform="SyNRA",
                verbose=False,
            )

            os.makedirs(os.path.dirname(output.warp), exist_ok=True)
            os.makedirs(os.path.dirname(output.jacobian), exist_ok=True)

            # fwdtransforms = [warp.nii.gz, affine.mat] for SyNRA
            warp_tmp = result["fwdtransforms"][0]
            shutil.copy(warp_tmp, output.warp)
            log_msg(f"Warp saved to {output.warp}")

            # Jacobian determinant of the deformation field (geometric, not log)
            jac = ants.create_jacobian_determinant_image(
                domain_image=fixed,
                tx=warp_tmp,
                do_log=False,
                geom=True,
            )
            ants.image_write(jac, output.jacobian)
            log_msg(f"Jacobian saved to {output.jacobian}")

        except Exception:
            logger.exception("compute_session_deformation failed")
            raise
