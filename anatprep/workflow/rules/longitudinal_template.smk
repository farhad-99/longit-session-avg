"""
Rule: build_subject_template

Per subject, per modality — aggregates all sessions:
  - Collect all trimmed session images for that subject and modality
  - Run ants.build_template() to produce a bias-corrected unbiased midpoint
    average across sessions
  - Save the subject template

Note: the input function below resolves trimmed session paths from the
per-(subject, modality) session list (get_modality_sessions), rather
than glob-ing the output directory or assuming every session has every
modality. A glob over not-yet-created outputs would always return an
empty list, breaking Snakemake's dependency tracking; deriving paths
from the discovered availability keeps the DAG correct.
"""


rule build_subject_template:
    """Build an unbiased subject template from all trimmed longitudinal sessions."""
    input:
        trimmed=lambda wildcards: [
            trimmed_path(wildcards.subject, ses, wildcards.modality)
            for ses in get_modality_sessions(wildcards.subject, wildcards.modality)
        ],
    output:
        template=os.path.join(
            output_dir,
            "sub-{subject}",
            "anat",
            "sub-{subject}_{modality}_desc-subjectTemplate_anat.nii.gz",
        ),
    threads: workflow.cores
    resources:
        mem_mb=8000,
        runtime=120,
    log:
        os.path.join("logs", "build_subject_template", "{subject}_{modality}.log"),
    run:
        import logging
        import os

        os.environ["ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS"] = str(threads)
        import ants

        logger = logging.getLogger(
            f"build_subject_template.{wildcards.subject}.{wildcards.modality}"
        )
        logger.setLevel(logging.INFO)
        logger.handlers = [logging.FileHandler(log[0])]
        log_msg = logger.info

        log_msg(f"Building template for sub-{wildcards.subject} {wildcards.modality}")
        log_msg(f"Input images: {input.trimmed}")

        try:
            image_list = [ants.image_read(f) for f in input.trimmed]

            template = ants.build_template(
                image_list=image_list,
                iterations=3,
                gradient_step=0.2,
                blending_weight=0.75,
                verbose=True,
            )

            os.makedirs(os.path.dirname(output.template), exist_ok=True)
            ants.image_write(template, output.template)
            log_msg(f"Saved subject template to {output.template}")
        except Exception:
            logger.exception("build_subject_template failed")
            raise
