	.file	"test_mmio_tx_only_compress_block.c"
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
# 79 "../testcase/test_mmio_tx_only.c" 1
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
	lw	a4,64(zero)
	li	a5,1073741824
	li	a3,1024
	sw	a3,8(a5)
	li	a5,1073741824
	li	a3,8192
	sw	a3,12(a5)
	li	a5,1073741824
	sw	a4,16(a5)
	li	a5,1073741824
	li	a4,5
	sw	a4,20(a5)
	li	a3,1073741824
	li	a5,1073741824
	li	a4,32
	sw	a4,24(a5)
	lw	a5,4(a3)
	li	a4,1
	li	a5,1073741824
	sw	a4,0(a5)
	li	a2,1073741824
	li	a5,1998848
	addi	a3,a3,4
	addi	a5,a5,1152
	li	a1,0
	li	a6,2
	addi	a2,a2,36
.L6:
	lw	a4,0(a3)
	andi	a0,a4,1
	beq	a0,zero,.L3
	mv	a1,a0
.L3:
	andi	a0,a4,4
	bne	a0,zero,.L4
	andi	a4,a4,3
	bne	a4,a6,.L5
	lw	a4,0(a2)
	or	a4,a4,a1
	bne	a4,zero,.L4
.L5:
	addi	a5,a5,-1
	bne	a5,zero,.L6
.L4:
	li	a5,1073741824
	addi	a5,a5,28
	lw	a5,0(a5)
	li	a5,1073741824
	addi	a5,a5,32
	lw	a5,0(a5)
	li	a5,1073741824
	addi	a5,a5,36
	lw	a5,0(a5)
	li	a5,8192
	lw	a5,0(a5)
	li	a5,8192
	addi	a5,a5,4
	lw	a5,0(a5)
	li	a5,8192
	addi	a5,a5,8
	lw	a5,0(a5)
	li	a5,8192
	addi	a5,a5,12
	lw	a5,0(a5)
	sw	zero,0(zero)
	ebreak
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
