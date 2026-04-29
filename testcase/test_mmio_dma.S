	.file	"test_mmio_dma.c"
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
# 120 "../testcase/test_mmio_dma.c" 1
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
	lui	a5,%hi(sw_iv_counter)
	lw	a2,64(zero)
	lw	a4,%lo(sw_iv_counter)(a5)
	li	a3,1128415232
	addi	a3,a3,817
	addi	a4,a4,1
	sw	a4,%lo(sw_iv_counter)(a5)
	lw	a5,%lo(sw_iv_counter)(a5)
	li	a4,1128407040
	addi	a4,a4,1841
	xor	a5,a2,a5
	xor	a5,a5,a4
	slli	a4,a5,13
	xor	a5,a5,a4
	srli	a4,a5,17
	xor	a5,a5,a4
	li	a4,1073741824
	sw	a3,40(a4)
	slli	a1,a5,5
	li	a4,979136512
	xor	a5,a5,a1
	addi	a4,a4,1070
	xor	a5,a5,a4
	li	a4,1073741824
	sw	a5,44(a4)
	lw	a5,44(a4)
	li	a4,-1640529920
	addi	a4,a4,-1607
	xor	a5,a5,a4
	slli	a4,a5,7
	srli	a5,a5,25
	or	a5,a5,a4
	li	a4,1073741824
	sw	a5,48(a4)
	lw	a5,48(a4)
	li	a4,1013903360
	addi	a4,a4,882
	add	a5,a5,a4
	srli	a4,a5,15
	slli	a5,a5,17
	or	a5,a5,a4
	li	a4,1073741824
	sw	a5,52(a4)
	li	a5,1073741824
	li	a4,1024
	sw	a4,8(a5)
	li	a5,1073741824
	li	a4,8192
	sw	a4,12(a5)
	li	a5,1073741824
	sw	a2,16(a5)
	li	a4,9
	li	a5,1073741824
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
	li	a3,1073741824
	lw	a5,28(a3)
	li	a2,8192
	li	a5,1073741824
	lw	a4,36(a5)
	li	a5,1073741824
	sw	a2,8(a5)
	li	a5,1073741824
	li	a2,16384
	sw	a2,12(a5)
	li	a5,1073741824
	sw	a4,16(a5)
	li	a5,1073741824
	li	a4,2
	sw	a4,20(a5)
	li	a2,1073741824
	li	a5,1073741824
	li	a4,32
	sw	a4,24(a5)
	lw	a5,4(a2)
	li	a4,1
	li	a5,1073741824
	sw	a4,0(a5)
	li	a5,1998848
	addi	a3,a3,28
	addi	a2,a2,4
	addi	a5,a5,1152
	li	a1,0
	li	a6,2
.L10:
	lw	a4,0(a2)
	andi	a0,a4,1
	beq	a0,zero,.L7
	mv	a1,a0
.L7:
	andi	a0,a4,4
	bne	a0,zero,.L8
	andi	a4,a4,3
	bne	a4,a6,.L9
	lw	a4,0(a3)
	or	a4,a4,a1
	bne	a4,zero,.L8
.L9:
	addi	a5,a5,-1
	bne	a5,zero,.L10
.L8:
	li	a5,1073741824
	addi	a5,a5,28
	lw	a5,0(a5)
	li	a5,64
.L11:
	addi	a5,a5,-1
	bne	a5,zero,.L11
	li	a5,16384
	lw	a5,0(a5)
	li	a5,16384
	addi	a5,a5,4
	lw	a5,0(a5)
	li	a5,16384
	addi	a5,a5,8
	lw	a5,0(a5)
	li	a5,16384
	addi	a5,a5,12
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
	.section	.sdata,"aw"
	.align	2
	.type	sw_iv_counter, @object
	.size	sw_iv_counter, 4
sw_iv_counter:
	.word	270544960
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
