	.file	"test_mmio_tx_encoder_error.c"
	.option nopic
	.attribute arch, "rv32i2p1"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.text,"ax",@progbits
	.align	2
	.globl	_start
	.type	_start, @function
_start:
 #APP
# 26 "../testcase/test_mmio_tx_encoder_error.c" 1
	li sp, 0x00007f00
j main

# 0 "" 2
 #NO_APP
	.size	_start, .-_start
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	li	a5,1073741824
	li	a4,1024
	sw	a4,8(a5)
	li	a5,1073741824
	li	a4,8192
	sw	a4,12(a5)
	li	a5,1073741824
	li	a4,576
	sw	a4,16(a5)
	li	a5,1073741824
	li	a4,9
	sw	a4,20(a5)
	li	a5,1073741824
	li	a4,32
	sw	a4,24(a5)
	li	a5,1073741824
	li	a4,1073741824
	li	a3,1
	li	a2,98304
	addi	a5,a5,4
	lw	a0,0(a5)
	addi	a2,a2,1696
	sw	a3,0(a4)
	li	a4,0
.L4:
	lw	a1,0(a5)
	addi	a4,a4,1
	andi	a3,a1,4
	bne	a3,zero,.L8
	bne	a4,a2,.L4
.L3:
	li	a5,1073741824
	lw	a6,28(a5)
	li	a5,1073741824
	lw	a2,32(a5)
	addi	a5,a0,-152
	snez	a5,a5
	bne	a3,zero,.L5
	ori	a5,a5,2
.L5:
	li	a3,4096
	addi	a3,a3,-16
	and	a3,a2,a3
	li	a7,96
	beq	a3,a7,.L6
	ori	a5,a5,4
.L6:
	li	a3,98304
	addi	a3,a3,1696
	bne	a4,a3,.L7
	ori	a5,a5,8
.L7:
	sw	a0,8(zero)
	sw	a1,12(zero)
	sw	a6,16(zero)
	sw	a2,20(zero)
	sw	a4,24(zero)
	sw	a5,4(zero)
	sw	zero,0(zero)
	ebreak
.L8:
	li	a3,4
	j	.L3
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
