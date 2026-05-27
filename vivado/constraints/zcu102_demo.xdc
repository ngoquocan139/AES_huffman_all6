## ZCU102 demo constraints for rv32_soc_fpga_zcu102_top.
##
## USER_SI570 is a 300 MHz differential clock on PL bank 64.
set_property PACKAGE_PIN AL8 [get_ports clk_p_i]
set_property PACKAGE_PIN AL7 [get_ports clk_n_i]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {clk_p_i clk_n_i}]

## User LEDs LED0..LED3.
set_property PACKAGE_PIN AG14 [get_ports {led_o[0]}]
set_property PACKAGE_PIN AF13 [get_ports {led_o[1]}]
set_property PACKAGE_PIN AE13 [get_ports {led_o[2]}]
set_property PACKAGE_PIN AJ14 [get_ports {led_o[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_o[*]}]

## USB-UART channel wired to PL:
## - uart_rx_i receives UART2_TXD_O_FPGA_RXD from the USB-UART bridge.
## - uart_tx_o drives UART2_RXD_I_FPGA_TXD into the USB-UART bridge.
set_property PACKAGE_PIN E13 [get_ports uart_rx_i]
set_property PACKAGE_PIN F13 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]
