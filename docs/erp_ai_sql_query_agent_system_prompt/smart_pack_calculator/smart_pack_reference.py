#!/usr/bin/env python3
import json
import math
import sys


PALLET_LENGTH_CM = 120.0
PALLET_WIDTH_CM = 80.0
PALLET_BASE_HEIGHT_CM = 14.5
GENERATED_BOX_MAX_NET_HEIGHT_CM = 165.5


def permutations3(a, b, c):
    return [
        [a, b, c],
        [a, c, b],
        [b, a, c],
        [b, c, a],
        [c, a, b],
        [c, b, a],
    ]


def best_fit_for_space(width, depth, height, outer_perms):
    best = {"count": 0, "nx": 0, "ny": 0, "nz": 0, "perm": None}
    for perm in outer_perms:
        nx = math.floor(width / perm[0]) if perm[0] else 0
        ny = math.floor(depth / perm[1]) if perm[1] else 0
        nz = math.floor(height / perm[2]) if perm[2] else 0
        count = nx * ny * nz
        if count > best["count"]:
            best = {"count": count, "nx": nx, "ny": ny, "nz": nz, "perm": perm}
    return best


def reverse_engineer_box(f_l, f_w, f_h, qty, i_l, i_w, i_h):
    for perm in permutations3(i_l, i_w, i_h):
        dx, dy, dz = perm
        max_nx = math.floor(f_l / dx)
        max_ny = math.floor(f_w / dy)
        max_nz = math.floor(f_h / dz)
        for x in range(1, max_nx + 1):
            for y in range(1, max_ny + 1):
                for z in range(1, max_nz + 1):
                    if x * y * z == qty:
                        return {"dx": dx, "dy": dy, "dz": dz, "nx": x, "ny": y, "nz": z}
    return None


def calculate_pallet_heuristic(box_x, box_y, box_z, gross, total_items, limit_h, limit_w):
    net_limit_h = limit_h - PALLET_BASE_HEIGHT_CM
    outer_perms = permutations3(box_x, box_y, box_z)
    best_layout = None
    max_total_boxes = -1

    for core_perm in outer_perms:
        cx = math.floor(PALLET_LENGTH_CM / core_perm[0])
        cy = math.floor(PALLET_WIDTH_CM / core_perm[1])
        cz = math.floor(net_limit_h / core_perm[2])
        if cx == 0 or cy == 0 or cz == 0:
            continue

        core_count = cx * cy * cz
        core_w = cx * core_perm[0]
        core_d = cy * core_perm[1]
        core_h = cz * core_perm[2]
        splits = [
            {"sxW": PALLET_LENGTH_CM - core_w, "sxD": PALLET_WIDTH_CM, "syW": core_w, "syD": PALLET_WIDTH_CM - core_d},
            {"sxW": PALLET_LENGTH_CM - core_w, "sxD": core_d, "syW": PALLET_LENGTH_CM, "syD": PALLET_WIDTH_CM - core_d},
        ]

        for split in splits:
            blocks = [{
                "type": "core",
                "x": 0,
                "y": 0,
                "z": PALLET_BASE_HEIGHT_CM,
                "dx": core_perm[0],
                "dy": core_perm[1],
                "dz": core_perm[2],
                "nx": cx,
                "ny": cy,
                "nz": cz,
                "count": core_count,
            }]

            side_x = best_fit_for_space(split["sxW"], split["sxD"], net_limit_h, outer_perms)
            if side_x["count"] > 0:
                blocks.append({
                    "type": "sideX",
                    "x": core_w,
                    "y": 0,
                    "z": PALLET_BASE_HEIGHT_CM,
                    "dx": side_x["perm"][0],
                    "dy": side_x["perm"][1],
                    "dz": side_x["perm"][2],
                    "nx": side_x["nx"],
                    "ny": side_x["ny"],
                    "nz": side_x["nz"],
                    "count": side_x["count"],
                })

            side_y = best_fit_for_space(split["syW"], split["syD"], net_limit_h, outer_perms)
            if side_y["count"] > 0:
                blocks.append({
                    "type": "sideY",
                    "x": 0,
                    "y": core_d,
                    "z": PALLET_BASE_HEIGHT_CM,
                    "dx": side_y["perm"][0],
                    "dy": side_y["perm"][1],
                    "dz": side_y["perm"][2],
                    "nx": side_y["nx"],
                    "ny": side_y["ny"],
                    "nz": side_y["nz"],
                    "count": side_y["count"],
                })

            top_max_w = min(PALLET_LENGTH_CM, core_w / 0.8)
            top_max_d = min(PALLET_WIDTH_CM, core_d / 0.8)
            top_max_h = net_limit_h - core_h
            if side_x["count"] > 0 and side_x["nz"] * side_x["perm"][2] > core_h:
                top_max_w = core_w
            if side_y["count"] > 0 and side_y["nz"] * side_y["perm"][2] > core_h:
                top_max_d = core_d

            top = best_fit_for_space(top_max_w, top_max_d, top_max_h, outer_perms)
            has_overhang = False
            if top["count"] > 0:
                blocks.append({
                    "type": "top",
                    "x": 0,
                    "y": 0,
                    "z": PALLET_BASE_HEIGHT_CM + core_h,
                    "dx": top["perm"][0],
                    "dy": top["perm"][1],
                    "dz": top["perm"][2],
                    "nx": top["nx"],
                    "ny": top["ny"],
                    "nz": top["nz"],
                    "count": top["count"],
                })
                has_overhang = top["nx"] * top["perm"][0] > core_w or top["ny"] * top["perm"][1] > core_d

            max_boxes_by_weight = math.floor((limit_w - 15.0) / gross) if gross else 0
            current_total = 0
            final_blocks = []
            for block in blocks:
                if current_total + block["count"] <= max_boxes_by_weight:
                    final_blocks.append(block)
                    current_total += block["count"]
                else:
                    allowed = max_boxes_by_weight - current_total
                    if allowed > 0:
                        truncated = dict(block)
                        truncated["count"] = allowed
                        final_blocks.append(truncated)
                    break

            if current_total > max_total_boxes:
                unique_orients = len({f"{b['dx']}-{b['dy']}-{b['dz']}" for b in final_blocks})
                max_total_boxes = current_total
                best_layout = {
                    "blocks": final_blocks,
                    "totalBoxes": current_total,
                    "hasOverhang": has_overhang,
                    "numBlocks": len(final_blocks),
                    "uniqueOrients": unique_orients,
                    "maxBoxesByWeight": max_boxes_by_weight,
                    "coreH": core_h,
                }

    return {"bestPalletLayout": best_layout, "maxTotalBoxes": max_total_boxes}


def evaluate_score(pallet_res, box_x, box_y, box_z, gross, total_items, l, w, h, limit_h, is_ozon_ok, is_wb_mono):
    layout = pallet_res["bestPalletLayout"]
    s1 = min(35.0, ((pallet_res["maxTotalBoxes"] * box_x * box_y * box_z) / (PALLET_LENGTH_CM * PALLET_WIDTH_CM * (limit_h - PALLET_BASE_HEIGHT_CM))) * 35.0)
    s2 = min(25.0, ((total_items * l * w * h) / (box_x * box_y * box_z)) * 25.0)
    base_area = sum((b["nx"] * b["dx"] * b["ny"] * b["dy"]) for b in layout["blocks"] if b["type"] != "top")
    s3 = (base_area / 9600.0) * 5.0 + (2.0 if layout["hasOverhang"] else 5.0) + 5.0
    max_d = max(box_x, box_y, box_z)
    min_d = min(box_x, box_y, box_z)
    ratio = max_d / min_d
    s4_ratio = 5.0 if ratio <= 3.0 else max(0.0, 5.0 - (ratio - 3.0) * 2.5)
    if 12.0 <= gross <= 18.0:
        s4_weight = 10.0
    elif gross < 12.0:
        s4_weight = (gross / 12.0) * 10.0
    else:
        s4_weight = max(0.0, (25.0 - gross) / 7.0 * 10.0)
    s4 = s4_weight + s4_ratio
    s5_block = 5.0 if layout["numBlocks"] <= 1 else (3.0 if layout["numBlocks"] <= 3 else 0.0)
    s5_orient = 5.0 if layout["uniqueOrients"] <= 1 else (3.0 if layout["uniqueOrients"] == 2 else 0.0)
    s5 = s5_block + s5_orient
    penalty = 20.0 if (not is_ozon_ok or is_wb_mono) else 0.0
    final_score = max(0.0, s1 + s2 + s3 + s4 + s5 - penalty)
    return {"finalScore": final_score, "s1": s1, "s2": s2, "s3": s3, "s4": s4, "s5": s5, "pen": penalty, "baseArea": base_area}


def normalize_xy(box_x, box_y):
    if box_x < box_y:
        return box_y, box_x, True
    return box_x, box_y, False


def plan_common(plan, pallet_res, eval_res, box_x, box_y, box_z, gross, total_items, limit_h, limit_w, hints):
    actual_boxes = pallet_res["maxTotalBoxes"]
    actual_items = actual_boxes * total_items
    return {
        **plan,
        "score": eval_res["finalScore"],
        "scores": eval_res,
        "actualItems": actual_items,
        "actualBoxes": actual_boxes,
        "palletBlocks": pallet_res["bestPalletLayout"]["blocks"],
        "palletGross": 15.0 + actual_boxes * gross,
        "limitH": limit_h,
        "limitW": limit_w,
        "hints": hints,
        "eff": (actual_boxes * box_x * box_y * box_z) / (PALLET_LENGTH_CM * PALLET_WIDTH_CM * (limit_h - PALLET_BASE_HEIGHT_CM)),
        "cargoBaseArea": eval_res["baseArea"],
    }


def trigger_sioc(l, w, h, weight, is_wb_mono, p_h, p_w):
    o_x, o_y = normalize_xy(l, w)[:2]
    o_z = h
    limit_h = min(p_h, 180.0) if is_wb_mono else p_h
    limit_w = min(p_w, 350.0) if is_wb_mono else p_w
    nx_p = math.floor(PALLET_LENGTH_CM / o_x)
    ny_p = math.floor(PALLET_WIDTH_CM / o_y)
    base_layers = math.floor((limit_h - PALLET_BASE_HEIGHT_CM) / o_z)
    max_boxes_by_h = nx_p * ny_p * base_layers
    max_boxes_by_w = math.floor((limit_w - 15.0) / weight)
    actual_boxes = min(max_boxes_by_h, max_boxes_by_w)
    if actual_boxes <= 0:
        return {"status": "error", "alert": "alert_reject", "message": "产品已完全击穿物流边界，拒绝装载。"}

    cargo_base_area = nx_p * o_x * ny_p * o_y
    s1 = min(35.0, ((actual_boxes * o_x * o_y * o_z) / (PALLET_LENGTH_CM * PALLET_WIDTH_CM * (limit_h - PALLET_BASE_HEIGHT_CM))) * 35.0)
    s2 = 25.0
    s3 = (cargo_base_area / 9600.0) * 5.0 + 5.0 + 5.0
    ratio = max(o_x, o_y, o_z) / min(o_x, o_y, o_z)
    s4 = (10.0 if 12.0 <= weight <= 18.0 else ((weight / 12.0) * 10.0 if weight < 12.0 else max(0.0, (25.0 - weight) / 7.0 * 10.0))) + (5.0 if ratio <= 3.0 else max(0.0, 5.0 - (ratio - 3.0) * 2.5))
    s5 = 10.0
    is_ozon_ok = o_x <= 120 and o_y <= 60 and o_z <= 50
    penalty = 20.0 if (not is_ozon_ok or is_wb_mono) else 0.0
    hints = ["hint_w_cap"] if actual_boxes == max_boxes_by_w and max_boxes_by_w < max_boxes_by_h else []

    return {
        "status": "ok",
        "mode": "sioc",
        "alert": "alert_sioc",
        "plans": [{
            "isFixedPlan": False,
            "isIrregular": False,
            "isDirect": True,
            "isWbMono": is_wb_mono,
            "isOzonOk": is_ozon_ok,
            "dimX": o_x,
            "dimY": o_y,
            "dimZ": o_z,
            "nx": 1,
            "ny": 1,
            "nz": 1,
            "weight": weight,
            "box_x": o_x,
            "box_y": o_y,
            "box_z": o_z,
            "totalItems": 1,
            "gross": weight,
            "score": max(0.0, s1 + s2 + s3 + s4 + s5 - penalty),
            "scores": {"s1": s1, "s2": s2, "s3": s3, "s4": s4, "s5": s5, "pen": penalty},
            "palletBlocks": [{"type": "core", "x": 0, "y": 0, "z": PALLET_BASE_HEIGHT_CM, "dx": o_x, "dy": o_y, "dz": o_z, "nx": nx_p, "ny": ny_p, "nz": base_layers, "count": actual_boxes}],
            "actualItems": actual_boxes,
            "actualBoxes": actual_boxes,
            "palletGross": 15.0 + actual_boxes * weight,
            "limitH": limit_h,
            "limitW": limit_w,
            "eff": (actual_boxes * o_x * o_y * o_z) / (PALLET_LENGTH_CM * PALLET_WIDTH_CM * (limit_h - PALLET_BASE_HEIGHT_CM)),
            "hints": hints,
            "cargoBaseArea": cargo_base_area,
        }],
    }


def smart_pack_calculate(data):
    l = float(data["length_cm"])
    w = float(data["width_cm"])
    h = float(data["height_cm"])
    weight = float(data["weight_kg"])
    p_h = float(data["pallet_limit_height_cm"])
    p_w = float(data["pallet_limit_weight_kg"])
    use_fixed = bool(data.get("use_fixed_box", False))

    max_edge = max(l, w, h)
    sum_edge = l + w + h
    if max_edge > 120 or sum_edge > 200:
        return {"status": "error", "alert": "alert_limit", "message": "商品单品尺寸已违反基础物流红线。"}

    is_wb_item_mono = max_edge > 80 or sum_edge > 160
    fixed_plan = None

    if use_fixed:
        fl = float(data["fixed_length_cm"])
        fw = float(data["fixed_width_cm"])
        fh = float(data["fixed_height_cm"])
        fqty = int(data["fixed_pcs"])
        fgw = float(data["fixed_gross_weight_kg"])
        if l * w * h * fqty > fl * fw * fh:
            return {"status": "error", "alert": "alert_vol", "message": "指定外箱容积小于商品总体积。"}
        if fgw > 350:
            return {"status": "error", "alert": "alert_overw", "message": "外箱单重超 350kg。"}

        box_x, box_y, _ = normalize_xy(fl, fw)
        box_z = fh
        is_ozon_ok = box_x <= 120 and box_y <= 60 and box_z <= 50
        is_wb_mono = is_wb_item_mono or box_x > 80 or (box_x + box_y + box_z) > 160
        limit_h = min(p_h, 180.0) if is_wb_mono else p_h
        limit_w = min(p_w, 350.0) if is_wb_mono else p_w
        inner = reverse_engineer_box(box_x, box_y, box_z, fqty, l, w, h)
        is_irregular = inner is None
        act_dx = 0 if is_irregular else inner["dx"]
        act_dy = 0 if is_irregular else inner["dy"]
        act_dz = 0 if is_irregular else inner["dz"]
        act_nx = 0 if is_irregular else inner["nx"]
        act_ny = 0 if is_irregular else inner["ny"]
        act_nz = 0 if is_irregular else inner["nz"]
        pal_res = calculate_pallet_heuristic(box_x, box_y, box_z, fgw, fqty, limit_h, limit_w)
        if pal_res["bestPalletLayout"] and pal_res["maxTotalBoxes"] > 0:
            eval_res = evaluate_score(pal_res, box_x, box_y, box_z, fgw, fqty, l, w, h, limit_h, is_ozon_ok, is_wb_mono)
            hints = ["hint_w_cap"] if pal_res["maxTotalBoxes"] == pal_res["bestPalletLayout"]["maxBoxesByWeight"] else []
            fixed_plan = plan_common({
                "isFixedPlan": True,
                "isIrregular": is_irregular,
                "isDirect": False,
                "isWbMono": is_wb_mono,
                "isOzonOk": is_ozon_ok,
                "dimX": act_dx,
                "dimY": act_dy,
                "dimZ": act_dz,
                "nx": act_nx,
                "ny": act_ny,
                "nz": act_nz,
                "weight": weight,
                "box_x": box_x,
                "box_y": box_y,
                "box_z": box_z,
                "totalItems": fqty,
                "gross": fgw,
                "actPadX": 0 if is_irregular else box_x - act_nx * act_dx,
                "actPadY": 0 if is_irregular else box_y - act_ny * act_dy,
                "actPadZ": 0 if is_irregular else box_z - act_nz * act_dz,
            }, pal_res, eval_res, box_x, box_y, box_z, fgw, fqty, limit_h, limit_w, hints)

    pool = []
    for p_in in permutations3(l, w, h):
        d_x, d_y, d_z = p_in
        lim_x = math.floor(PALLET_LENGTH_CM / d_x)
        lim_y = math.floor(PALLET_WIDTH_CM / d_y)
        lim_z = math.floor(GENERATED_BOX_MAX_NET_HEIGHT_CM / d_z)
        if lim_x == 0 or lim_y == 0 or lim_z == 0:
            continue
        for i in range(1, lim_x + 1):
            for j in range(1, lim_y + 1):
                for k in range(1, lim_z + 1):
                    total_items = i * j * k
                    if total_items <= 4 and total_items != 1 and total_items * weight < 5:
                        continue
                    if total_items == 1:
                        continue
                    gross = total_items * weight
                    if gross > 25.0:
                        continue
                    box_x = math.ceil(i * d_x + 1.5 + 0.5 + i * 0.2)
                    box_y = math.ceil(j * d_y + 1.5 + 0.5 + j * 0.2)
                    box_z = math.ceil(k * d_z + 1.5 + 0.5 + k * 0.2)
                    act_nx, act_ny, act_dx, act_dy = i, j, d_x, d_y
                    if box_x < box_y:
                        box_x, box_y = box_y, box_x
                        act_nx, act_ny = act_ny, act_nx
                        act_dx, act_dy = act_dy, act_dx
                    if box_x > 120 or box_y > 120 or box_z > 80:
                        continue
                    if any(p["box_x"] == box_x and p["box_y"] == box_y and p["box_z"] == box_z for p in pool):
                        continue
                    is_ozon_ok = box_x <= 120 and box_y <= 60 and box_z <= 50
                    is_wb_mono = is_wb_item_mono or box_x > 80 or (box_x + box_y + box_z) > 160
                    limit_h = min(p_h, 180.0) if is_wb_mono else p_h
                    limit_w = min(p_w, 350.0) if is_wb_mono else p_w
                    pal_res = calculate_pallet_heuristic(box_x, box_y, box_z, gross, total_items, limit_h, limit_w)
                    if pal_res["bestPalletLayout"] and pal_res["maxTotalBoxes"] > 0:
                        eval_res = evaluate_score(pal_res, box_x, box_y, box_z, gross, total_items, l, w, h, limit_h, is_ozon_ok, is_wb_mono)
                        hints = []
                        if pal_res["maxTotalBoxes"] == pal_res["bestPalletLayout"]["maxBoxesByWeight"]:
                            hints.append("hint_w_cap")
                        else:
                            if pal_res["bestPalletLayout"]["hasOverhang"]:
                                hints.append("hint_oh")
                            if ((pal_res["maxTotalBoxes"] * box_x * box_y * box_z) / (PALLET_LENGTH_CM * PALLET_WIDTH_CM * (limit_h - PALLET_BASE_HEIGHT_CM))) < 0.75:
                                needed_z = pal_res["bestPalletLayout"]["coreH"] + min(box_x, box_y, box_z)
                                if needed_z > (limit_h - PALLET_BASE_HEIGHT_CM) and not is_wb_mono:
                                    hints.append("hint_z_exp")
                        pool.append(plan_common({
                            "isFixedPlan": False,
                            "isIrregular": False,
                            "isDirect": False,
                            "isWbMono": is_wb_mono,
                            "isOzonOk": is_ozon_ok,
                            "dimX": act_dx,
                            "dimY": act_dy,
                            "dimZ": d_z,
                            "nx": act_nx,
                            "ny": act_ny,
                            "nz": k,
                            "weight": weight,
                            "box_x": box_x,
                            "box_y": box_y,
                            "box_z": box_z,
                            "totalItems": total_items,
                            "gross": gross,
                            "actPadX": box_x - act_nx * act_dx,
                            "actPadY": box_y - act_ny * act_dy,
                            "actPadZ": box_z - k * d_z,
                        }, pal_res, eval_res, box_x, box_y, box_z, gross, total_items, limit_h, limit_w, hints))

    compliant = [p for p in pool if p["isOzonOk"] and not p["isWbMono"]]
    if compliant:
        pool = compliant
    if not pool and not fixed_plan:
        return trigger_sioc(l, w, h, weight, is_wb_item_mono, p_h, p_w)

    pool.sort(key=lambda p: p["score"], reverse=True)
    if fixed_plan:
        pool = [p for p in pool if p["box_x"] != fixed_plan["box_x"] or p["box_y"] != fixed_plan["box_y"] or p["box_z"] != fixed_plan["box_z"]]
        plans = [fixed_plan] + pool[:2]
    else:
        plans = pool[:3]

    return {"status": "ok", "mode": "standard", "plans": plans}


if __name__ == "__main__":
    payload = json.load(sys.stdin)
    print(json.dumps(smart_pack_calculate(payload), ensure_ascii=False, indent=2))
