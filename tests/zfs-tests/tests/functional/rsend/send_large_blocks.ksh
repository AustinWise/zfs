#!/bin/ksh -p
# SPDX-License-Identifier: CDDL-1.0

#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright (c) 2026 by Austin Wise. All rights reserved.
#

. $STF_SUITE/tests/functional/rsend/rsend.kshlib

#
# Description:
#   Verify that incremental send/receive succeeds when the large_blocks 
#   feature was previously active but the current stream contains no large blocks.
#	Regression test for https://github.com/openzfs/zfs/issues/18101
#
# Strategy:
#   1. Create a dataset with 1MB recordsize.
#   2. Create and delete a large file to activate the large_blocks feature.
#   3. Send a full stream to a second dataset.
#   4. Attempt an incremental send back to the original dataset.
#

verify_runnable "both"

log_assert "Verify incremental receive handles inactive large_blocks feature correctly."

function cleanup
{
	cleanup_pool $POOL
	cleanup_pool $POOL2
}
log_onexit cleanup

typeset repro=$POOL/repro
typeset second=$POOL2/second

# Create a dataset with a large recordsize (1MB)
log_must zfs create -o recordsize=1M $repro
typeset mntpnt=$(get_prop mountpoint $repro)

# Activate the large_blocks feature by creating a large file, then delete it
# This leaves the feature 'active' on the dataset level even though large blocks no longer exist.
log_must dd if=/dev/urandom of=$mntpnt/big.bin bs=1M count=1
log_must zpool sync $POOL
log_must rm $mntpnt/big.bin

# Create initial snapshot and send to 'second' dataset.
# The send send will have the large blocks feature flag active but not actually contain any large blocks.
log_must zfs snapshot $repro@initial
log_must eval "zfs send -p -L $repro@initial | zfs receive $second"

# Ensure the the receiving pool has feature@large_blocks activated after receiving.
feat_val=$(zpool get -H -o value feature@large_blocks $POOL2)
log_note "Zpool $POOL2 feature@large_blocks=$feat_val"
if [[ "$feat_val" != "active" ]]; then
	log_fail "pool $POOL2 feature@large_blocks=$feat_val (expected 'active')"
fi

# Send an incremental stream back to the original dataset.
# The send stream should have the large_blocks feature flag despite no large blocks ever being
# born in the 'second' dataset.
log_must zfs snapshot $second@second
log_must eval "zfs send -L -i $second@initial $second@second | zfs receive -F $repro"

log_pass "Incremental receive succeeded."
