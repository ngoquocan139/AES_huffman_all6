## ZedBoard demo constraints for rv32_soc_fpga_demo_top.
## Verify these pins against the exact board schematic before final hardware demo.

set_property PACKAGE_PIN Y9 [get_ports clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]

set_property PACKAGE_PIN T22 [get_ports {led_o[0]}]
set_property PACKAGE_PIN T21 [get_ports {led_o[1]}]
set_property PACKAGE_PIN U22 [get_ports {led_o[2]}]
set_property PACKAGE_PIN U21 [get_ports {led_o[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_o[*]}]

## Demo UART pins. These are intended for a PL-side UART connection; confirm
## the chosen header pins before wiring external USB-UART hardware.
set_property PACKAGE_PIN AA9 [get_ports uart_rx_i]
set_property PACKAGE_PIN Y10 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]
