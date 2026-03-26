import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np
import pandas as pd
from sklearn.metrics import pairwise_distances
from tqdm import trange
import seaborn as sns
import sys
package_path = "E:/resarch_data/fMRI/toolboxpy/gradient/mapalign-master"
if package_path not in sys.path:
    sys.path.append(package_path)
from mapalign import embed


HEMI_TO_STRUCTURE = {
    "left": "CIFTI_STRUCTURE_CORTEX_LEFT",
    "right": "CIFTI_STRUCTURE_CORTEX_RIGHT",
}


def parse_args():
    parser = argparse.ArgumentParser(
        description="Merged Margulies pipeline: affinity, embedding, and plotting."
    )
    parser.add_argument("--dconn", required=True, help="Path to group dconn CIFTI file.")
    parser.add_argument(
        "--header-ref",
        required=True,
        help="Path to reference CIFTI file for extracting brain model header.",
    )
    parser.add_argument("--surf-gii", required=True, help="Path to hemisphere surface .gii file.")
    parser.add_argument("--out-basedir", required=True, help="Output base directory.")
    parser.add_argument(
        "--hemi",
        choices=("left", "right"),
        default="left",
        help="Hemisphere to process.",
    )
    return parser.parse_args()


def normalize(v):
    lo = np.min(v)
    hi = np.max(v)
    if hi <= lo:
        return np.zeros_like(v)
    return (v - lo) / (hi - lo)


def main():
    args = parse_args()

    out_base = Path(args.out_basedir)
    out_conn = out_base / "conn_matrices"
    out_emb = out_base / "embedded"
    out_img = out_base / "image"
    out_conn.mkdir(parents=True, exist_ok=True)
    out_emb.mkdir(parents=True, exist_ok=True)
    out_img.mkdir(parents=True, exist_ok=True)

    structure_name = HEMI_TO_STRUCTURE[args.hemi]

    print(f"[1/5] Load dconn: {args.dconn}")
    dconn_img = nib.load(args.dconn)
    dcon = dconn_img.get_fdata(dtype=np.float32)
    if dcon.ndim != 2 or dcon.shape[0] != dcon.shape[1]:
        raise ValueError(f"dconn must be square 2D matrix, got shape {dcon.shape}")
    n_full = dcon.shape[0]

    print(f"[2/5] Load header reference: {args.header_ref}")
    ref_img = nib.load(args.header_ref)
    bm_axis = ref_img.header.get_axis(1)
    bm_axis_dict = {
        name.item() if hasattr(name, "item") else name: index_slice
        for name, index_slice, _ in bm_axis.iter_structures()
    }
    if structure_name not in bm_axis_dict:
        raise KeyError(f"{structure_name} not found in reference header structures.")

    hemi_slice = bm_axis_dict[structure_name]
    vertices = bm_axis.vertex[hemi_slice]
    n_vertices = bm_axis.nvertices[structure_name]

    valid_mask = np.zeros(n_vertices, dtype=bool)
    valid_mask[vertices] = True

    if n_full != valid_mask.shape[0]:
        raise ValueError(
            f"dconn size ({n_full}) does not match selected hemi vertex count ({valid_mask.shape[0]})."
        )

    print("[3/5] Compute thresholded affinity")
    dcon_valid = dcon[np.ix_(valid_mask, valid_mask)].copy()
    n = dcon_valid.shape[0]
    perc = np.array([np.percentile(row, 90) for row in dcon_valid], dtype=np.float32)

    for i in trange(n, desc="Row threshold @90%"):
        dcon_valid[i, dcon_valid[i, :] < perc[i]] = 0

    neg_count = int(np.sum(dcon_valid < 0))
    if neg_count > 0:
        print(f"Set negative values to 0, count={neg_count}")
        dcon_valid[dcon_valid < 0] = 0

    aff = 1 - pairwise_distances(dcon_valid, metric="cosine")
    aff = np.nan_to_num(aff, nan=0.0, posinf=0.0, neginf=0.0).astype(np.float32)

    aff_path = out_conn / "aff_valid.npz"
    np.savez_compressed(
        aff_path,
        aff=aff,
        vertices=vertices.astype(np.int32),
        valid_mask=valid_mask,
        N_full=np.int32(n_full),
    )
    print(f"Saved: {aff_path}")

    print("[4/5] Diffusion embedding with mapalign")
    emb, res = embed.compute_diffusion_map(aff, alpha=0.5, return_result=True)
    emb_path = out_emb / "embedding_dense_emb.npy"
    res_path = out_emb / "embedding_dense_res.npy"
    np.save(emb_path, emb)
    np.save(res_path, res)
    print(f"Saved: {emb_path}")
    print(f"Saved: {res_path}")

    print("[5/5] Generate images")
    surf_coords = nib.load(args.surf_gii).darrays[0].data
    if surf_coords.shape[0] != valid_mask.shape[0]:
        raise ValueError(
            f"surf vertices ({surf_coords.shape[0]}) do not match hemi vertex count ({valid_mask.shape[0]})."
        )

    ref_data = ref_img.get_fdata()
    if ref_data.ndim == 2:
        if ref_data.shape[0] <= ref_data.shape[1]:
            cortex_ref = ref_data[0, hemi_slice]
        else:
            cortex_ref = ref_data[hemi_slice, 0]
    elif ref_data.ndim == 1:
        cortex_ref = ref_data[hemi_slice]
    else:
        raise ValueError(f"Unsupported reference data shape: {ref_data.shape}")

    fig, axes = plt.subplots(2, 2, figsize=(12, 10))
    axes = axes.flatten()

    panels = [
        ("Cortex Data", cortex_ref),
        ("Gradient 1", emb[:, 0]),
        ("Gradient 2", emb[:, 1] if emb.shape[1] > 1 else np.zeros(emb.shape[0])),
        ("Gradient 3", emb[:, 2] if emb.shape[1] > 2 else np.zeros(emb.shape[0])),
    ]
    for i, (title, values) in enumerate(panels):
        im = axes[i].scatter(
            surf_coords[valid_mask, 0],
            surf_coords[valid_mask, 1],
            c=values,
            cmap="Spectral",
            s=0.5,
        )
        axes[i].set_title(title)
        axes[i].set_aspect("equal", adjustable="datalim")
        fig.colorbar(im, ax=axes[i])

    fig.tight_layout()
    surface_png = out_img / "gradients_surface.png"
    fig.savefig(surface_png, dpi=200)
    plt.close(fig)
    print(f"Saved: {surface_png}")

    e0 = emb[:, 0].ravel()
    e1 = (emb[:, 1] * -1).ravel() if emb.shape[1] > 1 else np.zeros_like(e0)
    df = pd.DataFrame({"e0": e0, "e1": e1})

    n_g1 = normalize(df["e0"].values)
    n_g2 = normalize(df["e1"].values)
    n_g2_inv = normalize(-df["e1"].values)

    colors = np.ones((len(df), 4), dtype=np.float32)
    colors[:, 0] = n_g1
    colors[:, 1] = n_g2 * (1 - n_g1)
    colors[:, 2] = n_g2_inv * (1 - n_g1)

    sns.set(style="white")
    g = sns.JointGrid(x="e1", y="e0", data=df, height=10)
    g.ax_joint.scatter(df["e1"], df["e0"], c=colors, s=5, alpha=0.8, edgecolors="none")
    g.ax_marg_x.hist(df["e1"], color="gray", bins=100, alpha=0.3, histtype="stepfilled")
    g.ax_marg_y.hist(
        df["e0"],
        color="gray",
        bins=100,
        alpha=0.3,
        histtype="stepfilled",
        orientation="horizontal",
    )
    g.ax_joint.set_xlabel("Gradient 2")
    g.ax_joint.set_ylabel("Gradient 1")
    sns.despine(fig=g.fig)

    joint_png = out_img / "gradients_joint.png"
    g.fig.savefig(joint_png, dpi=200)
    plt.close(g.fig)
    print(f"Saved: {joint_png}")


if __name__ == "__main__":
    main()
