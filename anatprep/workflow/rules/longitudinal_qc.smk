"""
Rule: generate_qc_report

Per subject, per modality — after all sessions are processed:
  - Render orthogonal slice montages (axial/coronal/sagittal) for:
      * each trimmed session image
      * the subject template
      * each Jacobian determinant map
  - Write a multi-page PDF analogous to SPM's spm_print PS output

One page per image, three rows (axial/coronal/sagittal), 9 evenly-spaced
slices per row.  Jacobian pages use a diverging colormap centred at 1
(expansion > 1, contraction < 1).
"""


rule generate_qc_report:
    """Render multi-page PDF QC report for all sessions and the subject template."""
    input:
        trimmed=lambda wildcards: [
            os.path.join(
                output_dir,
                f"sub-{wildcards.subject}",
                f"ses-{ses}",
                "anat",
                f"sub-{wildcards.subject}_ses-{ses}_{wildcards.modality}_desc-trimmed_anat.nii.gz",
            )
            for ses in get_modality_sessions(wildcards.subject, wildcards.modality)
        ],
        template=os.path.join(
            output_dir,
            "sub-{subject}",
            "anat",
            "sub-{subject}_{modality}_desc-subjectTemplate_anat.nii.gz",
        ),
        jacobians=lambda wildcards: [
            os.path.join(
                output_dir,
                f"sub-{wildcards.subject}",
                f"ses-{ses}",
                "anat",
                f"sub-{wildcards.subject}_ses-{ses}_{wildcards.modality}_space-subjectTemplate_desc-jacobian_anat.nii.gz",
            )
            for ses in get_modality_sessions(wildcards.subject, wildcards.modality)
        ],
    output:
        pdf=os.path.join(
            output_dir,
            "sub-{subject}",
            "anat",
            "sub-{subject}_{modality}_desc-qc_anat.pdf",
        ),
    threads: 1
    resources:
        mem_mb=4000,
        runtime=15,
    log:
        os.path.join("logs", "generate_qc_report", "{subject}_{modality}.log"),
    run:
        import logging
        import numpy as np
        import nibabel as nib
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib.backends.backend_pdf import PdfPages
        from matplotlib.colors import TwoSlopeNorm

        logger = logging.getLogger(
            f"generate_qc_report.{wildcards.subject}.{wildcards.modality}"
        )
        logger.setLevel(logging.INFO)
        logger.handlers = [logging.FileHandler(log[0])]
        log_msg = logger.info

        try:
            sessions = get_modality_sessions(wildcards.subject, wildcards.modality)
            n_slices = 9

            def _load(path):
                img = nib.load(path)
                data = img.get_fdata(dtype=np.float32)
                return data

            def _montage_page(pdf, data, title, cmap="gray", vmin=None, vmax=None, norm=None):
                """Render one PDF page: axial / coronal / sagittal rows, n_slices each."""
                fig, axes = plt.subplots(3, n_slices, figsize=(n_slices * 1.6, 3 * 1.6))
                fig.suptitle(title, fontsize=9, y=1.01)

                orientations = [
                    ("Axial",    2, data[:, :, :]),
                    ("Coronal",  1, data[:, :, :]),
                    ("Sagittal", 0, data[:, :, :]),
                ]
                for row_idx, (label, axis, vol) in enumerate(orientations):
                    n = vol.shape[axis]
                    indices = np.linspace(int(n * 0.1), int(n * 0.9), n_slices, dtype=int)
                    for col_idx, idx in enumerate(indices):
                        ax = axes[row_idx, col_idx]
                        sl = np.take(vol, idx, axis=axis)
                        ax.imshow(
                            np.rot90(sl),
                            cmap=cmap,
                            vmin=vmin,
                            vmax=vmax,
                            norm=norm,
                            interpolation="nearest",
                            aspect="equal",
                        )
                        ax.axis("off")
                        if col_idx == 0:
                            ax.set_ylabel(label, fontsize=7, rotation=90, labelpad=2)

                plt.tight_layout(pad=0.3)
                pdf.savefig(fig, bbox_inches="tight")
                plt.close(fig)

            os.makedirs(os.path.dirname(output.pdf), exist_ok=True)
            log_msg(f"Writing QC PDF: {output.pdf}")

            with PdfPages(output.pdf) as pdf:
                # Metadata page info
                d = pdf.infodict()
                d["Title"] = f"sub-{wildcards.subject} {wildcards.modality} QC"
                d["Subject"] = "Longitudinal session-averaging QC"

                # One page per trimmed session
                for ses, path in zip(sessions, input.trimmed):
                    data = _load(path)
                    p1, p99 = np.percentile(data[data > 0], [1, 99])
                    _montage_page(
                        pdf, data,
                        title=f"Trimmed — sub-{wildcards.subject} ses-{ses} {wildcards.modality}",
                        vmin=p1, vmax=p99,
                    )
                    log_msg(f"  Added trimmed ses-{ses}")

                # Template page
                tmpl = _load(input.template)
                p1, p99 = np.percentile(tmpl[tmpl > 0], [1, 99])
                _montage_page(
                    pdf, tmpl,
                    title=f"Subject template — sub-{wildcards.subject} {wildcards.modality}",
                    vmin=p1, vmax=p99,
                )
                log_msg("  Added template")

                # One page per Jacobian determinant
                for ses, path in zip(sessions, input.jacobians):
                    jac = _load(path)
                    jac_clipped = np.clip(jac, 0.5, 2.0)
                    norm = TwoSlopeNorm(vmin=0.5, vcenter=1.0, vmax=2.0)
                    _montage_page(
                        pdf, jac_clipped,
                        title=f"Jacobian det — sub-{wildcards.subject} ses-{ses} {wildcards.modality}",
                        cmap="RdBu_r",
                        norm=norm,
                    )
                    log_msg(f"  Added Jacobian ses-{ses}")

            log_msg(f"QC PDF written: {output.pdf}")

        except Exception:
            logger.exception("generate_qc_report failed")
            raise
