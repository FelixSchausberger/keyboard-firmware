/*
Build a QMK firmware image from a pinned QMK tree with submodules.

The source is copied to a writable directory, the repository-side keymap is
injected into the QMK keyboard tree, and make is run with BUILD_DIR outside
the QMK tree so the build output cannot be swept into the source copy.

The derivation does not fetch submodules itself: `src` must already contain
them, e.g. a flake input declared with `submodules=1`.
*/
{
  lib,
  stdenv,
  gnumake,
  gcc-arm-embedded,
  python3,
  qmk,
  git,
  coreutils,
}: {
  pname,
  version,
  src,
  keyboard,
  keymap,
  keymapPath,
  artifacts ? ["bin"],
  meta ? {},
}:
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    gnumake
    gcc-arm-embedded
    python3
    qmk
    git
    coreutils
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontFixup = true;
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild

    cp -r ${src} qmk
    chmod -R u+w qmk

    mkdir -p qmk/keyboards/${keyboard}/keymaps
    cp -r ${keymapPath} qmk/keyboards/${keyboard}/keymaps/${keymap}
    chmod -R u+w qmk/keyboards/${keyboard}/keymaps/${keymap}

    export QMK_HOME="$PWD/qmk"
    export QMK_USERSPACE=
    export SKIP_GIT=yes

    make -C qmk -j"$(nproc)" BUILD_DIR="$PWD/build" ${keyboard}:${keymap}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    ${lib.concatMapStringsSep "\n" (
        ext: ''cp build/*.${ext} $out/''
      )
      artifacts}

    runHook postInstall
  '';

  meta =
    {
      description = "QMK firmware for ${keyboard} (${keymap})";
      license = lib.licenses.gpl2Plus;
      platforms = lib.platforms.linux;
    }
    // meta;
}
