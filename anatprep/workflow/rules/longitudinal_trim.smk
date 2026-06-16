"""
Rule: trim_and_center

Per session, per modality:
  - Load image with ANTsPy (ITK-backed, multithreaded)
  - Clip intensities at the 1st/99th percentile of foreground voxels using
    ANTs' iMath TruncateIntensity (computed in C++/ITK, not numpy)
  - Reset the image origin to the intensity-weighted centre of mass in
    world coordinates (via ants.get_center_of_mass), to normalise variable
    mouse positioning across sessions
  - Save the result under trimmed_data/, kept (not temp) so intermediate
    trimmed images remain available for inspection after the run
"""


rule trim_and_center:
    """Clip hot/cold voxels and re-centre the image origin to intensity-weighted COM."""
    input:
        nii=lambda wildcards: resolve_modality_nii(wildcards.subject, wildcards.session, wildcards.modality),
    output:
        nii=lambda wildcards: trimmed_path(wildcards.subject, wildcards.session, wildcards.modality),
    threads: workflow.cores
    resources:
        mem_mb=8000,
        runtime=30,
    log:
        os.path.join("logs", "trim_and_center", "{subject}_{session}_{modality}.log"),
    run:
        import logging
        import os

        os.environ["ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS"] = str(threads)
        import ants

        logger = logging.getLogger(
            f"trim_and_center.{wildcards.subject}.{wildcards.session}.{wildcards.modality}"
        )
        logger.setLevel(logging.INFO)
        logger.handlers = [logging.FileHandler(log[0])]
        log_msg = logger.info

        try:
            log_msg(f"Loading {input.nii}")
            img = ants.image_read(input.nii)

            fg_mask = ants.threshold_image(img, 1e-6, img.max(), 1, 0)
            if fg_mask.sum() == 0:
                raise ValueError(f"No foreground voxels found in {input.nii}")

            log_msg("Clipping intensities to [1st, 99th] percentile (foreground only)")
            trimmed = ants.iMath(img, "TruncateIntensity", 0.01, 0.99, 64, fg_mask)
            trimmed = trimmed * fg_mask

            com_world = ants.get_center_of_mass(trimmed)
            log_msg(f"COM world coords: {com_world}")

            trimmed.set_origin(tuple(-c for c in com_world))

            os.makedirs(os.path.dirname(output.nii), exist_ok=True)
            ants.image_write(trimmed, output.nii)
            log_msg(f"Saved trimmed image to {output.nii}")
        except Exception:
            logger.exception("trim_and_center failed")
            raise
