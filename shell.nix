{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.htop
    pkgs.git
    pkgs.julia_16-bin
  ];

  shellHook = ''
    echo "Circo Julia dev environment" 
  '';

  MY_ENVIRONMENT_VARIABLE = "world";
}
