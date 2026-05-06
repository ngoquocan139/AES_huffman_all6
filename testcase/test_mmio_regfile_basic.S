	.file	"test_mmio_regfile_basic.c"
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
# 28 "../testcase/test_mmio_regfile_basic.c" 1
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
	li	a6,1073741824
	li	a5,1073741824
	li	a4,8192
	lw	t1,4(a6)
	sw	a4,8(a5)
	li	a5,1073741824
	li	a4,16384
	sw	a4,12(a5)
	li	a5,1073741824
	li	a4,64
	sw	a4,16(a5)
	li	a0,1073741824
	li	a5,13
	sw	a5,20(a0)
	li	a1,1073741824
	li	a5,32
	sw	a5,24(a1)
	li	a5,287453184
	li	a2,1073741824
	addi	a5,a5,836
	sw	a5,40(a2)
	li	a5,1432776704
	li	a3,1073741824
	addi	a5,a5,1928
	sw	a5,44(a3)
	li	a5,-1716862976
	li	a4,1073741824
	addi	a5,a5,-1076
	li	a7,-571539456
	sw	a5,48(a4)
	addi	a7,a7,-256
	li	a5,1073741824
	sw	a7,52(a5)
	addi	a6,a6,4
	lw	a6,0(a6)
	lw	a7,20(a0)
	lw	t3,24(a1)
	lw	t4,40(a2)
	lw	a0,44(a3)
	lw	a1,48(a4)
	lw	a2,52(a5)
	li	a4,216
	snez	a5,t1
	beq	a6,a4,.L3
	ori	a5,a5,2
.L3:
	li	a4,13
	beq	a7,a4,.L4
	ori	a5,a5,4
.L4:
	li	a4,32
	beq	t3,a4,.L5
	ori	a5,a5,8
.L5:
	li	a4,287453184
	addi	a4,a4,836
	beq	t4,a4,.L6
	ori	a5,a5,16
.L6:
	li	a4,1432776704
	addi	a4,a4,1928
	beq	a0,a4,.L7
	ori	a5,a5,32
.L7:
	li	a4,-1716862976
	addi	a4,a4,-1076
	beq	a1,a4,.L8
	ori	a5,a5,64
.L8:
	li	a4,-571539456
	addi	a4,a4,-256
	beq	a2,a4,.L9
	ori	a5,a5,128
.L9:
	li	a4,1073741824
	li	a3,12
	sw	a3,0(a4)
	li	a3,2
	sw	a3,0(a4)
	addi	a4,a4,4
	lw	a4,0(a4)
	li	a3,16
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw a4, 0(a3)
# 0 "" 2
 #NO_APP
	beq	a4,zero,.L10
	ori	a5,a5,256
.L10:
	li	a4,1073741824
	addi	a4,a4,20
	lw	a4,0(a4)
	beq	a4,zero,.L11
	ori	a5,a5,512
.L11:
	li	a4,1073741824
	lw	a3,24(a4)
	li	a4,32
	beq	a3,a4,.L12
	ori	a5,a5,1024
.L12:
	li	a4,1073741824
	li	a3,1073741824
	addi	a4,a4,40
	lw	a4,0(a4)
	lw	t6,44(a3)
	li	a3,1073741824
	lw	t5,48(a3)
	li	a3,1073741824
	addi	a3,a3,52
	lw	a3,0(a3)
	or	a4,a4,t6
	or	a4,a4,t5
	or	a4,a4,a3
	beq	a4,zero,.L13
	li	a4,4096
	addi	a4,a4,-2048
	or	a5,a5,a4
.L13:
	li	a4,8
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw t1, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,12
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw a6, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,20
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw a7, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,24
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw t3, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,28
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw t4, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,32
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw a0, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,36
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw a1, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,40
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw a2, 0(a4)
# 0 "" 2
 #NO_APP
	li	a4,4
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw a5, 0(a4)
# 0 "" 2
 #NO_APP
	li	a5,1380270080
	addi	a5,a5,1841
	li	a4,0
 #APP
# 24 "../testcase/test_mmio_regfile_basic.c" 1
	sw a5, 0(a4)
# 0 "" 2
 #NO_APP
.L14:
	j	.L14
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
