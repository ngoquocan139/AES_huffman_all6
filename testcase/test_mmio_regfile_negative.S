	.file	"test_mmio_regfile_negative.c"
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
# 32 "../testcase/test_mmio_regfile_negative.c" 1
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
	li	a3,1073741824
	li	a5,1
	sw	a5,0(a3)
	li	a4,1073741824
	li	a2,8
	lw	a1,4(a4)
	sw	a2,0(a3)
	li	a3,-1
	sw	a3,4(a4)
	lw	a7,4(a4)
	srli	a5,a1,2
	xori	a5,a5,1
	andi	a4,a7,4
	andi	a5,a5,1
	bne	a4,zero,.L3
	ori	a5,a5,2
.L3:
	li	a4,1073741824
	li	a3,8
	sw	a3,0(a4)
	li	a3,305418240
	addi	a3,a3,1656
	sw	a3,252(a4)
	li	a4,1073741824
	lw	t1,4(a4)
	andi	a4,t1,4
	bne	a4,zero,.L4
	ori	a5,a5,4
.L4:
	li	a4,1073741824
	li	a3,8
	sw	a3,0(a4)
	li	a3,16
	sw	a3,20(a4)
	li	a3,1073741824
	lw	a6,4(a3)
	addi	a4,a4,20
	andi	a3,a6,4
	bne	a3,zero,.L5
	ori	a5,a5,8
.L5:
	lw	a4,0(a4)
	beq	a4,zero,.L6
	ori	a5,a5,16
.L6:
	li	a3,1073741824
	li	a4,8
	sw	a4,0(a3)
	li	a2,8192
	li	a4,1073741824
	sw	a2,8(a4)
	li	a4,1073741824
	li	a2,16384
	sw	a2,12(a4)
	li	a4,1073741824
	li	a2,64
	sw	a2,16(a4)
	li	a4,1073741824
	li	a2,13
	sw	a2,20(a4)
	li	a4,1073741824
	sw	zero,24(a4)
	lw	a0,24(a4)
	li	a4,1
	sw	a4,0(a3)
	li	a4,1073741824
	lw	a3,4(a4)
	andi	a4,a3,4
	bne	a4,zero,.L7
	ori	a5,a5,32
.L7:
	beq	a0,zero,.L8
	ori	a5,a5,64
.L8:
	li	a4,1073741824
	li	a2,8
	sw	a2,0(a4)
	li	a2,32
	sw	a2,24(a4)
	li	t3,13
	li	a4,1073741824
	sw	t3,20(a4)
	li	a2,-1
	sb	a2,20(a4)
	lw	a2,20(a4)
	beq	a2,t3,.L9
	ori	a5,a5,128
.L9:
	li	a4,1073741824
	li	t3,8
	sw	t3,0(a4)
	li	t3,1
	sw	t3,28(a4)
	li	a4,1073741824
	addi	a4,a4,4
	lw	a4,0(a4)
	andi	a4,a4,4
	bne	a4,zero,.L10
	ori	a5,a5,256
.L10:
	li	a4,1073741824
	li	t3,8
	sw	t3,0(a4)
	li	t3,1
	sw	t3,32(a4)
	li	a4,1073741824
	addi	a4,a4,4
	lw	a4,0(a4)
	andi	a4,a4,4
	bne	a4,zero,.L11
	ori	a5,a5,512
.L11:
	li	a4,8
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw a1, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,12
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw a7, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,16
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw t1, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,20
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw a6, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,24
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw a0, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,28
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw a2, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,32
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw a3, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,4
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw a5, 0(a4)
# 0 "" 2
 #NO_APP
	li	a5,1313161216
	addi	a5,a5,1841
	li	a4,0
 #APP
# 23 "../testcase/test_mmio_regfile_negative.c" 1
	sw a5, 0(a4)
# 0 "" 2
 #NO_APP
.L12:
	j	.L12
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
