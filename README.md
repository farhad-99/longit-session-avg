# longit-session-avg — within-subject longitudinal session averaging

Averages longitudinal MRI sessions per subject into a single unbiased
subject template, and registers every session back into that template's
space. Re-implements a MATLAB/SPM12/CAT12-style longitudinal pipeline in
Python using ANTsPy and nibabel (no MATLAB, no SPM).

## Workflow overview

```
trim_and_center                  (per subject/session/modality)
    ↓
build_subject_template            (per subject/modality, aggregates sessions)
    ↓
register_sessions_to_template     (per subject/session/modality)
    ↓
all                                (terminal rule: collects every output)
```

| Rule | Tool | Output |
|---|---|---|
| `trim_and_center` | nibabel | clipped + re-centred session image |
| `build_subject_template` | `ants.build_template()` | unbiased subject template |
| `register_sessions_to_template` | `ants.registration` (Rigid) | affine `.mat` + warped session image |
| `all` | — | requests every template + coregistered image |

## Requirements

- [ANTsPy](https://github.com/ANTsX/ANTsPy)
- [nibabel](https://nipy.org/nibabel/)
- Input BIDS derivatives dataset with TOF and T2w images:

```
{bids_dir}/sub-{subject}/ses-{session}/anat/sub-{subject}_ses-{session}_acq-TOF_run-1_angio.nii.gz
{bids_dir}/sub-{subject}/ses-{session}/anat/sub-{subject}_ses-{session}_run-1_T2w.nii.gz
```

Subjects and sessions are discovered automatically by globbing `bids_dir`
— no manifest file is needed. All sessions found for a subject are
aggregated as inputs to that subject's template.

## Usage

### 1. Edit the config (optional)

Open `anatprep/config/snakebids.yml` to change the modality filename
patterns, or pass `bids_dir`/`output_dir` on the command line.

### 2. Dry run

Pass `all` explicitly so there is no ambiguity about which rule is the
default target:

```bash
snakemake \
  --snakefile anatprep/workflow/Snakefile \
  --config \
    bids_dir=/path/to/bids \
    output_dir=/path/to/output \
  --cores all \
  --use-conda \
  -n all
```

### 3. Full run

```bash
snakemake \
  --snakefile anatprep/workflow/Snakefile \
  --config \
    bids_dir=/path/to/bids \
    output_dir=/path/to/output \
  --cores all \
  --use-conda \
  all
```

### 4. Cluster (SLURM)

```bash
snakemake \
  --snakefile anatprep/workflow/Snakefile \
  --config \
    bids_dir=/path/to/bids \
    output_dir=/path/to/output \
  --executor cluster-generic \
  --cluster-generic-submit-cmd "sbatch --mem={resources.mem_mb}M --time={resources.runtime} --cpus-per-task={threads}" \
  --use-conda \
  --jobs 32 \
  all
```

## Config keys

| Key | Required | Description |
|---|---|---|
| `bids_dir` | yes | Path to the BIDS derivatives dataset |
| `output_dir` | yes | Root output directory |
| `modalities` | no | Map of short modality key → BIDS filename suffix (defaults to TOF/T2w) |

## Output layout

```
{output_dir}/
  sub-{subject}/
    anat/
      sub-{subject}_{modality}_desc-subjectTemplate_anat.nii.gz
    ses-{session}/
      anat/
        sub-{subject}_ses-{session}_{modality}_desc-trimmed_anat.nii.gz
        sub-{subject}_ses-{session}_{modality}_space-subjectTemplate_desc-coregistered_anat.nii.gz
      xfm/
        sub-{subject}_ses-{session}_{modality}_from-session_to-subjectTemplate_0GenericAffine.mat
```

## Troubleshooting "Nothing to be done"

If Snakemake reports `Nothing to be done (all requested files are present
and up to date)` but the output directory is empty, delete the local
`.snakemake/` metadata directory in your working directory and rerun —
`.snakemake/` should never be committed to git (it is now in `.gitignore`).
