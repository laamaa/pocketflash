# BRIDGE and cartridge engine run directly from clk_74a. Status crosses into
# the pixel domain for display only; no displayed value controls operations.
derive_clock_uncertainty
set core_clocks [remove_from_collection [get_clocks *] [get_clocks {clk_74b bridge_spiclk}]]
set_clock_groups -asynchronous -group [get_clocks clk_74b] \
    -group [get_clocks bridge_spiclk] -group $core_clocks
set_false_path -from [get_registers {*app*}] -to [get_registers {*display*}]
set_false_path -from [get_registers {*flash*}] -to [get_registers {*display*}]
# External cartridge access is deliberately multi-cycle and sampled after 1us.
# Electrical setup/hold remains a hardware acceptance item.
set_false_path -from [get_ports {cart_tran_bank1[*] cart_tran_bank2[*] cart_tran_bank3[*]}]
