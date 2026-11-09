#!/usr/bin/env python3
"""MiniFire Unity - generate .meta files for every asset (deterministic GUIDs).
Chars get bottom-center pivot; everything uses PPU 100 sprites."""
import os, hashlib

ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets")
SKIP = {".DS_Store"}

def guid_for(rel):
    return hashlib.md5(("MiniFire::" + rel).encode()).hexdigest()

def write_meta(path, body):
    with open(path + ".meta", "w") as f:
        f.write("fileFormatVersion: 2\nguid: " + guid_for(os.path.relpath(path, ROOT)) + "\n" + body)

def texture_meta(sprite, bottom_pivot):
    pivot = "{x: 0.5, y: 0.0}" if bottom_pivot else "{x: 0.5, y: 0.5}"
    align = 7 if bottom_pivot else 0
    return f"""TextureImporter:
  internalIDToNameTable: []
  externalObjects: {{}}
  serializedVersion: 12
  mipmaps:
    mipMapMode: 0
    enableMipMap: 0
    sRGBTexture: 1
    linearTexture: 0
    fadeOut: 0
    borderMipMap: 0
    mipMapsPreserveCoverage: 0
    alphaTestReferenceValue: 0.5
    mipMapFadeDistanceStart: 1
    mipMapFadeDistanceEnd: 3
  bumpmap:
    convertToNormalMap: 0
    externalNormalMap: 0
    heightScale: 0.25
    normalMapFilter: 0
  isReadable: 0
  streamingMipmaps: 0
  streamingMipmapsPriority: 0
  vTOnly: 0
  grayScaleToAlpha: 0
  generateCubemap: 6
  cubemapConvolution: 0
  cubemapConvolutionSteps: 7
  cubemapConvolutionExclusion: 75
  serializedHeightMap: 0
  maxHeightTextureSize: 2048
  maxHeightTextureWidth: 0
  textureSettings:
    serializedVersion: 2
    filterMode: 1
    aniso: 1
    mipBias: 0
    wrapU: 1
    wrapV: 1
    wrapW: 1
  nPOTScale: 0
  lightmap: 0
  compressionQuality: 50
  spriteMode: 1
  spriteExtrude: 1
  spriteMeshType: 1
  alignment: {align}
  spritePivot: {pivot}
  spritePixelsToUnits: 100
  spriteBorder: {{x: 0, y: 0, z: 0, w: 0}}
  spriteGenerateFallbackPhysicsShape: 1
  alphaUsage: 1
  alphaIsTransparency: 1
  spriteTessellationDetail: -1
  textureType: 8
  textureShape: 1
  singleChannelComponent: 0
  flipbookRows: 0
  flipbookColumns: 0
  maxTextureSize: 2048
  textureSettings2:
    serializedVersion: 2
    filterMode: 1
    aniso: 1
    mipBias: 0
    wrapU: 1
    wrapV: 1
  spriteSheet:
    sprites: []
    outline: []
    physicsShape: []
    bones: []
    spriteID:
  spritePackingTag:
  pSDRemoveMatte: 0
  pSDShowRemoveMatteOption: 0
  userData:
  assetBundleName:
  assetBundleVariant:
"""

SCRIPT_META = """MonoImporter:
  externalObjects: {}
  serializedVersion: 2
  defaultReferences: []
  executionOrder: 0
  icon: {instanceID: 0}
  userData:
  assetBundleName:
  assetBundleVariant:
"""

FOLDER_META = """folderAsset: yes
DefaultImporter:
  externalObjects: {}
  userData:
  assetBundleName:
  assetBundleVariant:
"""

DEFAULT_META = """DefaultImporter:
  externalObjects: {}
  userData:
  assetBundleName:
  assetBundleVariant:
"""

AUDIO_META = """AudioImporter:
  externalObjects: {}
  serializedVersion: 7
  defaultSettings:
    serializedVersion: 2
    loadType: 0
    sampleRateSetting: 0
    defaultSampleRate: 44100
    optimizationLevel: 0
    compressionFormat: 0
    quality: 1
    conversionMode: 0
    preloadAudioData: 0
  platformSettingOverrides: {}
  forceToMono: 0
  normalize: 1
  loadInBackground: 0
  ambisonic: 0
  userData:
  assetBundleName:
  assetBundleVariant:
"""

count = 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if not d.startswith(".")]
    for name in dirnames:
        p = os.path.join(dirpath, name)
        write_meta(p, FOLDER_META); count += 1
    for fn in filenames:
        if fn in SKIP or fn.endswith(".meta"): continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, ROOT)
        if fn.endswith(".cs"):
            write_meta(p, SCRIPT_META)
        elif fn.endswith(".png"):
            write_meta(p, texture_meta(True, rel.startswith("Art" + os.sep + "Chars" + os.sep)))
        elif fn.endswith(".wav"):
            write_meta(p, AUDIO_META)
        else:
            write_meta(p, DEFAULT_META)
        count += 1

print("metas written:", count)
