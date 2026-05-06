	.file	"test_mmio_dma_storage_table.c"
	.option nopic
	.attribute arch, "rv32i2p1"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	_start
	.type	_start, @function
_start:
 #APP
# 61 "../testcase/test_mmio_dma_storage_table.c" 1
	li sp, 0x00007f00
j main

# 0 "" 2
 #NO_APP
	.size	_start, .-_start
	.align	2
	.globl	main
	.type	main, @function
main:
	lui	a1,%hi(sw_iv_counter)
	lw	t0,64(zero)
	lw	a3,68(zero)
	lw	a5,%lo(sw_iv_counter)(a1)
	li	a4,1128407040
	addi	a4,a4,816
	addi	a5,a5,1
	sw	a5,%lo(sw_iv_counter)(a1)
	lw	a5,%lo(sw_iv_counter)(a1)
	addi	sp,sp,-16
	li	a2,1128415232
	xor	a5,t0,a5
	xor	a5,a5,a4
	slli	a4,a5,13
	xor	a5,a5,a4
	srli	a4,a5,17
	sw	ra,12(sp)
	xor	a5,a5,a4
	addi	a2,a2,816
	li	a4,1073741824
	sw	a2,40(a4)
	slli	a0,a5,5
	li	a4,979136512
	xor	a5,a5,a0
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
	li	a4,8192
	sw	a4,8(a5)
	li	a5,1073741824
	li	a4,16384
	sw	a4,12(a5)
	li	a5,1073741824
	sw	t0,16(a5)
	li	a4,9
	li	a5,1073741824
	sw	a4,20(a5)
	li	a2,1073741824
	li	a5,1073741824
	li	a4,32
	sw	a4,24(a5)
	lw	a5,4(a2)
	li	a4,1
	li	a5,1073741824
	sw	a4,0(a5)
	li	a0,1073741824
	li	a5,1998848
	addi	a2,a2,4
	addi	a5,a5,1152
	li	a6,0
	li	t1,2
	addi	a0,a0,36
.L6:
	lw	a4,0(a2)
	andi	a7,a4,1
	beq	a7,zero,.L3
	mv	a6,a7
.L3:
	andi	a7,a4,4
	bne	a7,zero,.L4
	andi	a4,a4,3
	bne	a4,t1,.L5
	lw	a4,0(a0)
	or	a4,a4,a6
	bne	a4,zero,.L4
.L5:
	addi	a5,a5,-1
	bne	a5,zero,.L6
.L4:
	li	a5,1073741824
	addi	a5,a5,28
	lw	a5,0(a5)
	li	a7,1073741824
	li	a5,1073741824
	addi	a5,a5,32
	lw	a5,0(a5)
	li	a2,1073741824
	li	a4,1073741824
	li	a6,1073741824
	li	a0,1073741824
	li	t2,1
	lw	t1,36(a7)
	lw	t6,40(a6)
	lw	t5,44(a2)
	lw	t4,48(a4)
	lw	t3,52(a0)
	sw	t2,256(zero)
	sw	t2,260(zero)
	li	a5,8192
	sw	a5,264(zero)
	li	a5,16384
	sw	a5,268(zero)
	sw	t0,272(zero)
	sw	t1,276(zero)
	li	t0,9
	sw	t0,280(zero)
	lw	a5,40(a6)
	addi	a7,a7,36
	sw	a5,284(zero)
	lw	a5,44(a2)
	sw	a5,288(zero)
	lw	a5,48(a4)
	sw	a5,292(zero)
	lw	a5,52(a0)
	sw	a5,296(zero)
	lw	a5,%lo(sw_iv_counter)(a1)
	addi	a5,a5,1
	sw	a5,%lo(sw_iv_counter)(a1)
	lw	a5,%lo(sw_iv_counter)(a1)
	li	a1,1128407040
	addi	a1,a1,818
	xor	a5,a3,a5
	xor	a5,a5,a1
	slli	a1,a5,13
	xor	a5,a5,a1
	srli	a1,a5,17
	xor	a5,a5,a1
	li	a1,1128415232
	addi	a1,a1,818
	sw	a1,40(a6)
	slli	ra,a5,5
	li	a1,979136512
	addi	a1,a1,1070
	xor	a5,a5,ra
	xor	a5,a5,a1
	sw	a5,44(a2)
	lw	a5,44(a2)
	li	a2,-1640529920
	addi	a2,a2,-1607
	xor	a5,a5,a2
	slli	a2,a5,7
	srli	a5,a5,25
	or	a5,a5,a2
	sw	a5,48(a4)
	lw	a5,48(a4)
	li	a4,1013903360
	addi	a4,a4,882
	add	a5,a5,a4
	srli	a4,a5,15
	slli	a5,a5,17
	or	a5,a5,a4
	sw	a5,52(a0)
	li	a4,12288
	li	a5,1073741824
	sw	a4,8(a5)
	li	a5,1073741824
	li	a4,20480
	sw	a4,12(a5)
	li	a5,1073741824
	sw	a3,16(a5)
	li	a5,1073741824
	sw	t0,20(a5)
	li	a2,1073741824
	li	a5,1073741824
	li	a4,32
	sw	a4,24(a5)
	lw	a5,4(a2)
	addi	a2,a2,4
	li	a5,1073741824
	sw	t2,0(a5)
	li	a5,1998848
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
	lw	a4,0(a7)
	or	a4,a4,a1
	bne	a4,zero,.L8
.L9:
	addi	a5,a5,-1
	bne	a5,zero,.L10
.L8:
	li	a5,1073741824
	addi	a5,a5,28
	lw	a5,0(a5)
	li	a4,1
	li	a5,1073741824
	addi	a5,a5,32
	lw	a5,0(a5)
	li	a2,3
	li	a5,1073741824
	addi	a5,a5,36
	lw	a5,0(a5)
	sw	a4,320(zero)
	sw	a2,324(zero)
	li	a2,12288
	sw	a2,328(zero)
	li	a2,20480
	sw	a2,332(zero)
	sw	a3,336(zero)
	sw	a5,340(zero)
	li	a5,9
	sw	a5,344(zero)
	li	a5,1073741824
	addi	a5,a5,40
	lw	a5,0(a5)
	sw	a5,348(zero)
	li	a5,1073741824
	addi	a5,a5,44
	lw	a5,0(a5)
	sw	a5,352(zero)
	li	a5,1073741824
	addi	a5,a5,48
	lw	a5,0(a5)
	sw	a5,356(zero)
	li	a5,1073741824
	addi	a5,a5,52
	lw	a5,0(a5)
	sw	a5,360(zero)
	lw	a5,256(zero)
	bne	a5,a4,.L11
	lw	a4,260(zero)
	beq	a4,a5,.L12
.L11:
	lw	a4,320(zero)
	li	a5,1
	bne	a4,a5,.L12
	lw	a5,324(zero)
.L12:
	lw	a5,260(zero)
	li	a4,16384
	li	a5,1073741824
	sw	t6,40(a5)
	li	a5,1073741824
	sw	t5,44(a5)
	li	a5,1073741824
	sw	t4,48(a5)
	li	a5,1073741824
	sw	t3,52(a5)
	li	a5,1073741824
	sw	a4,8(a5)
	li	a5,1073741824
	li	a4,24576
	sw	a4,12(a5)
	li	a5,1073741824
	sw	t1,16(a5)
	li	a4,2
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
	addi	a2,a2,28
.L16:
	lw	a4,0(a3)
	andi	a0,a4,1
	beq	a0,zero,.L13
	mv	a1,a0
.L13:
	andi	a0,a4,4
	bne	a0,zero,.L14
	andi	a4,a4,3
	bne	a4,a6,.L15
	lw	a4,0(a2)
	or	a4,a4,a1
	bne	a4,zero,.L14
.L15:
	addi	a5,a5,-1
	bne	a5,zero,.L16
.L14:
	li	a5,1073741824
	addi	a5,a5,28
	lw	a5,0(a5)
	li	a5,1073741824
	addi	a5,a5,32
	lw	a5,0(a5)
	li	a5,64
.L17:
	addi	a5,a5,-1
	bne	a5,zero,.L17
	sw	zero,0(zero)
	ebreak
	.size	main, .-main
	.section	.sdata,"aw"
	.align	2
	.type	sw_iv_counter, @object
	.size	sw_iv_counter, 4
sw_iv_counter:
	.word	826366246
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
