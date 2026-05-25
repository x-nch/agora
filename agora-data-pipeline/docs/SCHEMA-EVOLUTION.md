# Schema Evolution

## Compatibility Modes

| Topic | Compatibility | Rationale |
|---|---|---|
| All default topics | BACKWARD | New consumers can read old data |
| incidents | FORWARD_TRANSITIVE | Incident schema evolves with new anomaly types |
| signal.commands | BACKWARD | Safety-critical — strict compatibility |

## AVRO Schema Registry

- Centralized schema storage via Confluent Schema Registry
- All topics use AVRO with Schema Registry integration
- Producers and consumers reference schema by ID
- Schema changes must follow compatibility rules

## Best Practices

1. **Adding fields**: Add with defaults (null or sensible default)
2. **Removing fields**: Deprecate in documentation first, remove after all consumers updated
3. **Renaming fields**: Add new field with old name as alias, migrate consumers, remove old field
4. **Changing types**: Only to wider compatible types (int → long, float → double)
5. **Transitive compatibility**: For incidents topic, all intermediate schemas are checked
