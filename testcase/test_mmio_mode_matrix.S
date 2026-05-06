	.file	"test_mmio_mode_matrix.c"
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
# 36 "../testcase/test_mmio_mode_matrix.c" 1
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
	li	a4,8192
	sw	a4,8(a5)
	li	a5,1073741824
	li	a4,16384
	sw	a4,12(a5)
	li	a4,32
	li	a5,1073741824
	sw	a4,16(a5)
	li	a5,1073741824
	sw	a4,24(a5)
	li	a4,1073741824
	addi	a4,a4,20
	li	a5,1
	sw	a5,0(a4)
	li	a3,1073741824
	li	a2,5
	lw	t1,4(a3)
	sw	a2,0(a4)
	lw	a7,4(a3)
	addi	a5,t1,-24
	li	a3,88
	snez	a5,a5
	beq	a7,a3,.L3
	ori	a5,a5,2
.L3:
	li	a3,9
	sw	a3,0(a4)
	li	a4,1073741824
	lw	a6,4(a4)
	li	a4,152
	beq	a6,a4,.L4
	ori	a5,a5,4
.L4:
	li	a4,1073741824
	li	a3,13
	sw	a3,20(a4)
	li	a3,1073741824
	lw	a0,4(a3)
	li	a3,216
	addi	a4,a4,20
	beq	a0,a3,.L5
	ori	a5,a5,8
.L5:
	li	a3,2
	sw	a3,0(a4)
	li	a3,1073741824
	lw	a1,4(a3)
	li	a4,40
	addi	a3,a3,4
	beq	a1,a4,.L6
	ori	a5,a5,16
.L6:
	li	a4,1073741824
	sw	zero,20(a4)
	lw	a2,0(a3)
	addi	a4,a4,20
	beq	a2,zero,.L7
	ori	a5,a5,32
.L7:
	li	a3,3
	sw	a3,0(a4)
	li	a4,1073741824
	lw	a3,4(a4)
	li	a4,48
	beq	a3,a4,.L8
	ori	a5,a5,64
.L8:
	li	a4,1073741824
	li	t3,8
	sw	t3,0(a4)
	li	t3,16
	sw	t3,20(a4)
	li	a4,1073741824
	addi	a4,a4,4
	lw	a4,0(a4)
	andi	t3,a4,4
	bne	t3,zero,.L9
	ori	a5,a5,128
.L9:
	li	t3,8
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw t1, 0(t3)
# 0 "" 2
 #NO_APP
	li	t1,12
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a7, 0(t1)
# 0 "" 2
 #NO_APP
	li	a7,16
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a6, 0(a7)
# 0 "" 2
 #NO_APP
	li	a6,20
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a0, 0(a6)
# 0 "" 2
 #NO_APP
	li	a0,24
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a1, 0(a0)
# 0 "" 2
 #NO_APP
	li	a1,28
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a2, 0(a1)
# 0 "" 2
 #NO_APP
	li	a2,32
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a3, 0(a2)
# 0 "" 2
 #NO_APP
	li	a3,36
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a4, 0(a3)
# 0 "" 2
 #NO_APP
	li	a4,4
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a5, 0(a4)
# 0 "" 2
 #NO_APP
	li	a5,1297039360
	addi	a5,a5,1093
	li	a4,0
 #APP
# 20 "../testcase/test_mmio_mode_matrix.c" 1
	sw a5, 0(a4)
# 0 "" 2
 #NO_APP
.L10:
	j	.L10
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
