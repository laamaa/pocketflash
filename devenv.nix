{ pkgs, ... }:
{
  packages = with pkgs; [
    python3
    iverilog
    gnumake
  ];
}
