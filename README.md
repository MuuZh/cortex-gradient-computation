# Compute Embeddings Release

This folder contains a two-step workflow for computing group-level cortical connectivity matrices from CIFTI dense time series and then generating Margulies-style diffusion map embeddings.

Files included:

- `run_batch.ps1`
- `run_margulies_pipeline_batch.ps1`
- `margulies_pipeline_merged.py`

## External requirements

You need the following external tools before running this workflow:

- Connectome Workbench command-line tool: https://www.humanconnectome.org/software/workbench-command
- `mapalign`: https://github.com/sensein/mapalign

You will also need a working Python environment with the packages imported by `margulies_pipeline_merged.py`, including:

- `numpy`
- `pandas`
- `nibabel`
- `matplotlib`
- `seaborn`
- `scikit-learn`
- `tqdm`

## What the workflow does

The workflow is intended to be run in this order:

1. Run `run_batch.ps1`
2. Run `run_margulies_pipeline_batch.ps1`

Step 1 creates group-level left/right cortical dense connectivity (`.dconn.nii`) files from a directory of subject-level `.dtseries.nii` files.

Step 2 takes those group-level `.dconn.nii` files and computes diffusion map embeddings, affinity matrices, and summary figures.

## Hard-coded paths that must be edited

Before using these scripts on your own data, you must update several hard-coded paths.

### In `run_batch.ps1`

Edit these variables near the top of the script:

- `$wb`
  - Path to `wb_command.exe` from Connectome Workbench.
- `$dtseriesdir`
  - Directory containing the input subject `.dtseries.nii` files.
- `$outDir`
  - Output directory where the group connectivity results and log files will be written.

### In `run_margulies_pipeline_batch.ps1`

Edit these defaults / job entries:

- `$PythonExe`
  - Python executable to use, if `python` on PATH is not the correct environment.
- `$PipelineScript`
  - Path to `margulies_pipeline_merged.py`.
- `$Jobs`
  - This is the main batch configuration. Each job must define:
    - `dconn`: input group `.dconn.nii` file
    - `header_ref`: reference CIFTI file used to recover the brain model / hemisphere header
    - `surf_gii`: hemisphere surface `.surf.gii` file used for plotting
    - `out_basedir`: output directory for this embedding job
    - `hemi`: `left` or `right`

### In `margulies_pipeline_merged.py`

Edit this line:

- `package_path`
  - Path to your local `mapalign` source directory if it is not already installed in a way that Python can import directly.

## Step 1: Run `run_batch.ps1`

### Input requirements

`run_batch.ps1` expects:

- A directory of subject-level CIFTI dense time series files (`*.dtseries.nii`)
- A valid Connectome Workbench installation, with `wb_command` available via the `$wb` path

The script processes all `*dtseries.nii` files found in `$dtseriesdir`.

### What it does

For each input `.dtseries.nii` file, the script:

- separates left and right cortex data
- creates left/right dense time series files
- computes left/right correlation matrices
- applies Fisher z-transformation

After processing all subjects, it computes the group average separately for left and right hemisphere and also converts the averaged z-values back to correlation values.

### Outputs

The main outputs written to `$outDir` are:

- `group_L_zcorr.dconn.nii`
- `group_R_zcorr.dconn.nii`
- `group_L_r.dconn.nii`
- `group_R_r.dconn.nii`

It also writes:

- a transcript log: `transcript_YYYYMMDD_HHMMSS.log`
- a Workbench log: `wb_YYYYMMDD_HHMMSS.log`
- temporary intermediate files under `$outDir\tmp`

### Example

From PowerShell:

```powershell
cd compute_embeddings_release
.\run_batch.ps1
```

## Step 2: Run `run_margulies_pipeline_batch.ps1`

### Input requirements

`run_margulies_pipeline_batch.ps1` expects:

- Python with the required packages installed
- access to `margulies_pipeline_merged.py`
- `mapalign` available through the hard-coded `package_path` or your Python environment
- one or more group-level `.dconn.nii` files produced by Step 1
- one reference CIFTI file per dataset / hemisphere configuration (`header_ref`)
- one matching surface GIFTI file (`surf_gii`) for each hemisphere

### What it does

For each job in `$Jobs`, the script calls:

```powershell
python margulies_pipeline_merged.py --dconn ... --header-ref ... --surf-gii ... --out-basedir ... --hemi ...
```

The Python script then:

- loads the group `.dconn.nii`
- extracts the hemisphere brain model from the reference CIFTI header
- thresholds each row at the 90th percentile
- sets negative values to zero
- computes a cosine-similarity affinity matrix
- runs diffusion map embedding with `mapalign`
- saves embedding arrays
- generates surface and joint scatter plots

### Outputs

For each job, outputs are written to `out_basedir` with this structure:

- `conn_matrices/aff_valid.npz`
- `embedded/embedding_dense_emb.npy`
- `embedded/embedding_dense_res.npy`
- `image/gradients_surface.png`
- `image/gradients_joint.png`

### Example

From PowerShell:

```powershell
cd compute_embeddings_release
.\run_margulies_pipeline_batch.ps1
```

If needed, you can also specify a Python executable explicitly:

```powershell
.\run_margulies_pipeline_batch.ps1 -PythonExe C:\path\to\python.exe
```

## Notes for users adapting this release

- The scripts are currently written with explicit local paths and are not yet parameterized for general distribution.
- Before sharing or reusing them, check every dataset-specific path in the PowerShell job lists.
- `header_ref` must come from a CIFTI file whose brain model matches the hemisphere and vertex layout expected by the `.dconn.nii` file.
- `surf_gii` must match the same hemisphere and vertex count.
