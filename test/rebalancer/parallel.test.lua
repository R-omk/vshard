test_run = require('test_run').new()

REPLICASET_1 = { 'box_1_a', 'box_1_b' }
REPLICASET_2 = { 'box_2_a', 'box_2_b' }
REPLICASET_3 = { 'box_3_a', 'box_3_b' }
REPLICASET_4 = { 'box_4_a', 'box_4_b' }
engine = test_run:get_cfg('engine')

test_run:create_cluster(REPLICASET_1, 'rebalancer')
test_run:create_cluster(REPLICASET_2, 'rebalancer')
test_run:create_cluster(REPLICASET_3, 'rebalancer')
test_run:create_cluster(REPLICASET_4, 'rebalancer')
util = require('util')
util.wait_master(test_run, REPLICASET_1, 'box_1_a')
util.wait_master(test_run, REPLICASET_2, 'box_2_a')
util.wait_master(test_run, REPLICASET_3, 'box_3_a')
util.wait_master(test_run, REPLICASET_4, 'box_4_a')
util.map_evals(test_run, {REPLICASET_1, REPLICASET_2, REPLICASET_3, \
                          REPLICASET_4}, 'bootstrap_storage(\'%s\')', engine)

--
-- The test is about parallel rebalancer. It is not very different
-- from a normal rebalancer except the problem of max receiving
-- bucket limit. Workers should correctly handle that, and of
-- course rebalancing should never totally stop.
--

util.map_evals(test_run, {REPLICASET_1, REPLICASET_2}, 'add_replicaset()')
util.map_evals(test_run, {REPLICASET_1, REPLICASET_2, REPLICASET_3}, 'add_second_replicaset()')
-- 4 replicasets, 1 sends to 3. It has 5 workers. It means, that
-- throttling is inevitable.
util.map_evals(test_run, {REPLICASET_1, REPLICASET_2, REPLICASET_3, REPLICASET_4}, [[\
    cfg.rebalancer_max_receiving = 1\
    vshard.storage.cfg(cfg, box.info.uuid)\
]])

test_run:switch('box_1_a')
vshard.storage.bucket_force_create(1, 200)
t1 = fiber.time()
wait_rebalancer_state('The cluster is balanced ok', test_run)
t2 = fiber.time()
-- Rebalancing should not stop. It can be checked by watching if
-- there was a sleep REBALANCER_WORK_INTERVAL (which is 10
-- seconds).
(t2 - t1 < 10) or {t1, t2}

test_run:switch('default')
test_run:drop_cluster(REPLICASET_4)
test_run:drop_cluster(REPLICASET_3)
test_run:drop_cluster(REPLICASET_2)
test_run:drop_cluster(REPLICASET_1)
