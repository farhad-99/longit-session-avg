"""
Rule: all (terminal rule)

Requests all subject template files and all coregistered session images
for both modalities across all subjects and sessions.

This is the default Snakemake target. To target it unambiguously, pass
`all` explicitly on the command line: `snakemake ... all`.
"""


rule all:
    """Collect all subject templates and coregistered session images.

    Only requests (subject, session, modality) combinations that were
    actually discovered on disk — not every session necessarily has
    every modality acquired.
    """
    input:
        templates=[
            os.path.join(
                output_dir,
                f"sub-{sub}",
                "anat",
                f"sub-{sub}_{mod}_desc-subjectTemplate_anat.nii.gz",
            )
            for sub in subjects
            for mod in modalities
            if get_modality_sessions(sub, mod)
        ],
        coregistered=[
            os.path.join(
                output_dir,
                f"sub-{sub}",
                f"ses-{ses}",
                "anat",
                f"sub-{sub}_ses-{ses}_{mod}_space-subjectTemplate_desc-coregistered_anat.nii.gz",
            )
            for sub in subjects
            for mod in modalities
            for ses in get_modality_sessions(sub, mod)
        ],
