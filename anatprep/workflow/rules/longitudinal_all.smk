"""
Rule: all (terminal rule)

Requests all subject template files, coregistered session images,
deformation fields, Jacobian determinant maps, and QC PDFs
for both modalities across all subjects and sessions.

This is the default Snakemake target. To target it unambiguously, pass
`all` explicitly on the command line: `snakemake ... all`.
"""


rule all:
    """Collect all outputs: templates, coregistered images, Jacobians, warps, QC PDFs.

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
        warps=[
            os.path.join(
                output_dir,
                f"sub-{sub}",
                f"ses-{ses}",
                "xfm",
                f"sub-{sub}_ses-{ses}_{mod}_from-session_to-subjectTemplate_desc-warp_anat.nii.gz",
            )
            for sub in subjects
            for mod in modalities
            for ses in get_modality_sessions(sub, mod)
        ],
        jacobians=[
            os.path.join(
                output_dir,
                f"sub-{sub}",
                f"ses-{ses}",
                "anat",
                f"sub-{sub}_ses-{ses}_{mod}_space-subjectTemplate_desc-jacobian_anat.nii.gz",
            )
            for sub in subjects
            for mod in modalities
            for ses in get_modality_sessions(sub, mod)
        ],
        qc_pdfs=[
            os.path.join(
                output_dir,
                f"sub-{sub}",
                "anat",
                f"sub-{sub}_{mod}_desc-qc_anat.pdf",
            )
            for sub in subjects
            for mod in modalities
            if get_modality_sessions(sub, mod)
        ],

