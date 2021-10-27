/*  Copyright (C) 1996-1997  Id Software, Inc.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

 See file, 'COPYING', for details.
 */

#pragma once

#include <common/bspfile.hh>
#include <common/mathlib.hh>
#include <string>

#include <common/qvec.hh>

const dmodelh2_t *BSP_GetWorldModel(const mbsp_t *bsp);
int Face_GetNum(const mbsp_t *bsp, const mface_t *f);

// bounds-checked array access (assertion failure on out-of-bounds)
const bsp2_dnode_t *BSP_GetNode(const mbsp_t *bsp, int nodenum);
const mleaf_t *BSP_GetLeaf(const mbsp_t *bsp, int leafnum);
const mleaf_t *BSP_GetLeafFromNodeNum(const mbsp_t *bsp, int nodenum);
const dplane_t *BSP_GetPlane(const mbsp_t *bsp, int planenum);
const mface_t *BSP_GetFace(const mbsp_t *bsp, int fnum);
const gtexinfo_t *BSP_GetTexinfo(const mbsp_t *bsp, int texinfo);
mface_t *BSP_GetFace(mbsp_t *bsp, int fnum);

int Face_VertexAtIndex(const mbsp_t *bsp, const mface_t *f, int v);
const qvec3f &Face_PointAtIndex(const mbsp_t *bsp, const mface_t *f, int v);
qplane3d Face_Plane(const mbsp_t *bsp, const mface_t *f);
const gtexinfo_t *Face_Texinfo(const mbsp_t *bsp, const mface_t *face);
const miptex_t *Face_Miptex(const mbsp_t *bsp, const mface_t *face);
const rgba_miptex_t *Face_RgbaMiptex(const mbsp_t *bsp, const mface_t *face);
const char *Face_TextureName(const mbsp_t *bsp, const mface_t *face);
bool Face_IsLightmapped(const mbsp_t *bsp, const mface_t *face);
const qvec3f &GetSurfaceVertexPoint(const mbsp_t *bsp, const mface_t *f, int v);
bool ContentsOrSurfaceFlags_IsTranslucent(const mbsp_t *bsp, int contents_or_surf_flags); // mxd
bool Face_IsTranslucent(const mbsp_t *bsp, const mface_t *face); // mxd
int Face_ContentsOrSurfaceFlags(
    const mbsp_t *bsp, const mface_t *face); // mxd. Returns CONTENTS_ value for Q1, Q2_SURF_ bitflags for Q2...
const dmodelh2_t *BSP_DModelForModelString(const mbsp_t *bsp, const std::string &submodel_str);
bool Light_PointInSolid(const mbsp_t *bsp, const dmodelh2_t *model, const qvec3d &point);
bool Light_PointInWorld(const mbsp_t *bsp, const qvec3d &point);
/**
 * Searches for a face touching a point and facing a certain way.
 * Sometimes (water, sky?) there will be 2 overlapping candidates facing opposite ways, the provided normal
 * is used to disambiguate these.
 */
const mface_t *BSP_FindFaceAtPoint(
    const mbsp_t *bsp, const dmodelh2_t *model, const qvec3d &point, const qvec3d &wantedNormal);

const qvec3f &Face_PointAtIndex(const mbsp_t *bsp, const mface_t *f);
const qvec3f &Vertex_GetPos(const mbsp_t *bsp, int num);
qvec3d Face_Normal(const mbsp_t *bsp, const mface_t *f);
std::vector<qvec3f> GLM_FacePoints(const mbsp_t *bsp, const mface_t *face);
qvec3f Face_Centroid(const mbsp_t *bsp, const mface_t *face);
void Face_DebugPrint(const mbsp_t *bsp, const mface_t *face);
