# Client Configurations

Producer and consumer configuration presets for 60K msg/sec throughput on MSK Express.

## Producer Config (IoT Gateway)

- acks=all + idempotence for safety-critical city data
- 64KB batches with 10ms linger for throughput
- Snappy compression (30-40% smaller)
- 128MB buffer per producer

## Consumer Config (Stream Processors)

- Manual commits after processing complete
- 500 records max per poll
- 45s session timeout, 15s heartbeat
- 50MB max fetch per request
