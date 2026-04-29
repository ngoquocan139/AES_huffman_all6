	.file	"test_cpu_instruction_cov.c"
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
# 151 "../testcase/test_cpu_instruction_cov.c" 1
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
 #APP
# 166 "../testcase/test_cpu_instruction_cov.c" 1
	lui a0, 0x12345
# 0 "" 2
 #NO_APP
	li	a4,-1985228800
	addi	a4,a4,-529
	li	a3,5
 #APP
# 30 "../testcase/test_cpu_instruction_cov.c" 1
	add  a5,  a4, a3
sub  t6,  a4, a3
sll  t5,  a4, a3
slt  t4,  a4, a3
sltu t3, a4, a3
xor  t1,  a4, a3
srl  a7,  a4, a3
sra  a6,  a4, a3
or   a1,   a4, a3
and  a2,  a4, a3

# 0 "" 2
 #NO_APP
	xor	a5,a5,t6
	xor	a5,a5,t5
	xor	a5,a5,t4
	xor	a5,a5,t3
	xor	a5,a5,t1
	xor	a5,a5,a7
	xor	a5,a5,a6
	xor	a5,a5,a1
	xor	a5,a5,a2
	li	a4,291
 #APP
# 62 "../testcase/test_cpu_instruction_cov.c" 1
	addi a3, a4, -17
# 0 "" 2
# 64 "../testcase/test_cpu_instruction_cov.c" 1
	slti a2, a4, -1
# 0 "" 2
 #NO_APP
	xor	a3,a3,a2
 #APP
# 66 "../testcase/test_cpu_instruction_cov.c" 1
	sltiu a2, a4, 16
# 0 "" 2
 #NO_APP
	xor	a3,a3,a2
 #APP
# 68 "../testcase/test_cpu_instruction_cov.c" 1
	xori a2, a4, 0x55
# 0 "" 2
 #NO_APP
	xor	a3,a3,a2
 #APP
# 70 "../testcase/test_cpu_instruction_cov.c" 1
	ori a2, a4, 0x2a
# 0 "" 2
 #NO_APP
	xor	a3,a3,a2
 #APP
# 72 "../testcase/test_cpu_instruction_cov.c" 1
	andi a2, a4, 0x7f
# 0 "" 2
 #NO_APP
	xor	a3,a3,a2
 #APP
# 74 "../testcase/test_cpu_instruction_cov.c" 1
	slli a2, a4, 3
# 0 "" 2
 #NO_APP
	xor	a3,a3,a2
 #APP
# 76 "../testcase/test_cpu_instruction_cov.c" 1
	srli a2, a4, 2
# 0 "" 2
 #NO_APP
	xor	a3,a3,a2
 #APP
# 78 "../testcase/test_cpu_instruction_cov.c" 1
	srai a2, a4, 2
# 0 "" 2
 #NO_APP
	li	a6,0
	xor	t3,a3,a2
	li	a4,1
	li	a1,2
 #APP
# 88 "../testcase/test_cpu_instruction_cov.c" 1
	beq  a4, a4, 1f
ori  a6, a6, 0x100
1:
ori  a6, a6, 0x001
bne  a4, a1, 2f
ori  a6, a6, 0x200
2:
ori  a6, a6, 0x002
blt  a4, a1, 3f
ori  a6, a6, 0x400
3:
ori  a6, a6, 0x004
bge  a1, a4, 4f
ori  a6, a6, 0x400
4:
ori  a6, a6, 0x008
bltu a4, a1, 5f
ori  a6, a6, 0x080
5:
ori  a6, a6, 0x010
bgeu a1, a4, 6f
ori  a6, a6, 0x080
6:
ori  a6, a6, 0x020

# 0 "" 2
 #NO_APP
	li	a1,-1582120960
	addi	a1,a1,980
	li	a7,-8192
	sw	a1,256(zero)
	addi	a7,a7,1429
	sh	a7,260(zero)
	li	a1,122
	li	a4,256
	sb	a1,262(zero)
 #APP
# 133 "../testcase/test_cpu_instruction_cov.c" 1
	lbu t5, 0(a4)
# 0 "" 2
# 134 "../testcase/test_cpu_instruction_cov.c" 1
	lb  t4, 3(a4)
# 0 "" 2
# 135 "../testcase/test_cpu_instruction_cov.c" 1
	lhu a1, 4(a4)
# 0 "" 2
# 136 "../testcase/test_cpu_instruction_cov.c" 1
	lh  a4, 4(a4)
# 0 "" 2
 #NO_APP
	li	t1,212
	bne	t5,t1,.L10
	li	t1,-95
	bne	t4,t1,.L11
	li	t1,57344
	addi	t1,t1,1429
	bne	a1,t1,.L12
	bne	a4,a7,.L13
.L3:
	li	a4,847659008
	addi	a4,a4,513
	add	a4,a5,a4
	snez	a4,a4
	bne	a3,a2,.L4
	ori	a4,a4,2
.L4:
	li	a3,63
	beq	a6,a3,.L5
	ori	a4,a4,4
.L5:
	li	a3,57344
	addi	a3,a3,1429
	beq	a1,a3,.L6
	ori	a4,a4,8
.L6:
	li	a3,305418240
	beq	a0,a3,.L7
	ori	a4,a4,16
.L7:
	li	a3,0
 #APP
# 183 "../testcase/test_cpu_instruction_cov.c" 1
	la t0, 1f
jalr zero, 0(t0)
ori a3, a3, 0x100
1:
ori a3, a3, 0x1

# 0 "" 2
 #NO_APP
	li	a2,1
	beq	a3,a2,.L8
	ori	a4,a4,32
.L8:
	li	a3,20
 #APP
# 14 "../testcase/test_cpu_instruction_cov.c" 1
	sw t3, 0(a3)
# 0 "" 2
 #NO_APP
	li	a3,16
 #APP
# 14 "../testcase/test_cpu_instruction_cov.c" 1
	sw a6, 0(a3)
# 0 "" 2
 #NO_APP
	li	a3,12
 #APP
# 14 "../testcase/test_cpu_instruction_cov.c" 1
	sw a1, 0(a3)
# 0 "" 2
 #NO_APP
	li	a3,8
 #APP
# 14 "../testcase/test_cpu_instruction_cov.c" 1
	sw a5, 0(a3)
# 0 "" 2
 #NO_APP
	li	a5,4
 #APP
# 14 "../testcase/test_cpu_instruction_cov.c" 1
	sw a4, 0(a5)
# 0 "" 2
 #NO_APP
	li	a5,1129336832
	addi	a5,a5,1347
	li	a4,0
 #APP
# 14 "../testcase/test_cpu_instruction_cov.c" 1
	sw a5, 0(a4)
# 0 "" 2
 #NO_APP
.L9:
	j	.L9
.L10:
	li	a1,-1
	j	.L3
.L11:
	li	a1,-2
	j	.L3
.L12:
	li	a1,-3
	j	.L3
.L13:
	li	a1,-4
	j	.L3
	.size	main, .-main
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
