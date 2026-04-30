	.file	"test_cpu_mem_forward_cov.c"
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
# 106 "../testcase/test_cpu_mem_forward_cov.c" 1
	li sp, 0x00007f00
jal zero, main

# 0 "" 2
 #NO_APP
	.size	_start, .-_start
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	li	a2,17
	sb	a2,768(zero)
	li	a4,-126
	sb	a4,769(zero)
	li	a3,51
	sb	a3,770(zero)
	li	a4,-12
	sb	a4,771(zero)
	li	a4,16384
	addi	a4,a4,1383
	sh	a4,784(zero)
	li	a4,-28672
	addi	a4,a4,-1621
	sh	a4,786(zero)
	li	a4,324509696
	addi	a4,a4,-1057
	li	a5,768
	sw	a4,800(zero)
 #APP
# 36 "../testcase/test_cpu_mem_forward_cov.c" 1
	lbu a6, 0(a5)
# 0 "" 2
# 37 "../testcase/test_cpu_mem_forward_cov.c" 1
	lbu a0, 1(a5)
# 0 "" 2
# 38 "../testcase/test_cpu_mem_forward_cov.c" 1
	lbu a1, 2(a5)
# 0 "" 2
# 39 "../testcase/test_cpu_mem_forward_cov.c" 1
	lbu a5, 3(a5)
# 0 "" 2
 #NO_APP
	li	a4,1
	bne	a6,a2,.L3
	li	a2,130
	bne	a0,a2,.L3
	bne	a1,a3,.L3
	addi	a5,a5,-244
	snez	a4,a5
.L3:
	li	a5,768
 #APP
# 43 "../testcase/test_cpu_mem_forward_cov.c" 1
	lb a2, 1(a5)
# 0 "" 2
# 44 "../testcase/test_cpu_mem_forward_cov.c" 1
	lb a5, 3(a5)
# 0 "" 2
 #NO_APP
	li	a3,-126
	bne	a2,a3,.L4
	li	a3,-12
	beq	a5,a3,.L5
.L4:
	ori	a4,a4,2
.L5:
	li	a5,784
 #APP
# 48 "../testcase/test_cpu_mem_forward_cov.c" 1
	lhu a2, 0(a5)
# 0 "" 2
# 49 "../testcase/test_cpu_mem_forward_cov.c" 1
	lhu a5, 2(a5)
# 0 "" 2
 #NO_APP
	li	a3,16384
	addi	a3,a3,1383
	bne	a2,a3,.L6
	li	a3,36864
	addi	a3,a3,-1621
	beq	a5,a3,.L7
.L6:
	ori	a4,a4,4
.L7:
	li	a3,784
 #APP
# 53 "../testcase/test_cpu_mem_forward_cov.c" 1
	lh a3, 2(a3)
# 0 "" 2
 #NO_APP
	li	a5,-28672
	addi	a5,a5,-1621
	beq	a3,a5,.L8
	ori	a4,a4,8
.L8:
	li	a3,20480
	addi	a3,a3,1450
	li	a5,768
 #APP
# 62 "../testcase/test_cpu_mem_forward_cov.c" 1
	sh a3, 1(a5)
# 0 "" 2
 #NO_APP
	li	a3,-1515888640
	addi	a3,a3,-1446
 #APP
# 63 "../testcase/test_cpu_mem_forward_cov.c" 1
	sw a3, 2(a5)
# 0 "" 2
# 64 "../testcase/test_cpu_mem_forward_cov.c" 1
	lh a3, 1(a5)
# 0 "" 2
# 65 "../testcase/test_cpu_mem_forward_cov.c" 1
	lw a5, 2(a5)
# 0 "" 2
 #NO_APP
	li	a5,832
 #APP
# 78 "../testcase/test_cpu_mem_forward_cov.c" 1
	li   t0, 0x12345000
addi t0, t0, 0x678
add  t1, t0, t0
xor  t2, t1, t0
sw   t2, 0(a5)
lw   t3, 0(a5)
add  t4, t3, t0
sw   t4, 4(a5)
jal  t5, 1f
addi t6, zero, 0x7f
1:
add  a5, t5, t5
add  a1, t4, t3
add  a2, t0, t1
add  a3, t2, t3

# 0 "" 2
 #NO_APP
	xor	a5,a5,a1
	xor	a5,a5,a2
	lw	a2,836(zero)
	xor	a5,a5,a3
	snez	a3,a4
	xor	a1,a5,a2
	bne	a5,a2,.L9
	ori	a3,a3,2
.L9:
	li	a5,12
 #APP
# 13 "../testcase/test_cpu_mem_forward_cov.c" 1
	sw a1, 0(a5)
# 0 "" 2
 #NO_APP
	li	a5,8
 #APP
# 13 "../testcase/test_cpu_mem_forward_cov.c" 1
	sw a4, 0(a5)
# 0 "" 2
 #NO_APP
	li	a5,4
 #APP
# 13 "../testcase/test_cpu_mem_forward_cov.c" 1
	sw a3, 0(a5)
# 0 "" 2
 #NO_APP
	li	a5,1129336832
	addi	a5,a5,1352
	li	a4,0
 #APP
# 13 "../testcase/test_cpu_mem_forward_cov.c" 1
	sw a5, 0(a4)
# 0 "" 2
 #NO_APP
.L10:
	j	.L10
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
