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

## Local paths

The scripts do not contain local absolute paths. Provide local paths at runtime through PowerShell parameters, a job CSV, or environment variables.

### `run_batch.ps1`

Required paths:

- `-WorkbenchCommand`: path to `wb_command.exe` from Connectome Workbench. You may also set the `WB_COMMAND` environment variable.
- `-DtseriesDir`: directory containing input subject `.dtseries.nii` files. The script scans this directory only, not nested subdirectories.
- `-OutDir`: output directory for group connectivity results and log files.

### `run_margulies_pipeline_batch.ps1`

The batch embedding script reads jobs from a CSV file. Required columns:

- `dconn`: input group `.dconn.nii` file
- `header_ref`: reference CIFTI file used to recover the brain model / hemisphere header
- `surf_gii`: hemisphere surface `.surf.gii` file used for plotting
- `out_basedir`: output directory for this embedding job
- `hemi`: `left` or `right`

If `mapalign` is not installed in your Python environment, set `MAPALIGN_PATH` to the local `mapalign` source directory before running `margulies_pipeline_merged.py`.

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
.\run_batch.ps1 -WorkbenchCommand "<path-to-wb_command.exe>" -DtseriesDir "<dtseries-dir>" -OutDir "<group-dconn-output-dir>"
```

## Step 2: Run `run_margulies_pipeline_batch.ps1`

### Input requirements

`run_margulies_pipeline_batch.ps1` expects:

- Python with the required packages installed
- access to `margulies_pipeline_merged.py`
- `mapalign` available through `MAPALIGN_PATH` or your Python environment
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
.\run_margulies_pipeline_batch.ps1 -JobConfig "<jobs.csv>"
```

If needed, you can also specify a Python executable explicitly:

```powershell
.\run_margulies_pipeline_batch.ps1 -JobConfig "<jobs.csv>" -PythonExe "<python-executable>"
```

## Notes for users adapting this release

- Keep dataset-specific paths in your local job CSV or command-line invocation, not in this repository.
- `header_ref` must come from a CIFTI file whose brain model matches the hemisphere and vertex layout expected by the `.dconn.nii` file.
- `surf_gii` must match the same hemisphere and vertex count.
