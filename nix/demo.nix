{ pkgs, appBundle }:
let
  python = pkgs.python3.withPackages (packages: [ packages.pillow ]);
in
pkgs.runCommand "keyfinder-demo"
  {
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    meta.mainProgram = "keyfinder-demo";
  }
  ''
    makeWrapper ${pkgs.lib.getExe python} "$out/bin/keyfinder-demo" \
      --add-flags ${../scripts/render-demo.py} \
      --add-flags "--app ${appBundle}/Applications/Keyfinder.app" \
      --add-flags "--font ${pkgs.inter}/share/fonts/truetype/InterVariable.ttf"
  ''
