if {[file exists work]} {
  vdel -lib work -all
}
vlib work
vmap work work

vlog +incdir+rtl \
  rtl/aes128_cipher_core.v \
  rtl/aes128_key_expansion.v \
  rtl/aes128_cipher_top.v \
  tb/tb_aes128_round_wave.v

vsim -voptargs=+acc work.test_bench
do sim/aes128_round_wave.do
run -all
