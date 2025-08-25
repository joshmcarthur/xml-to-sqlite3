# SQL Query Examples

This document provides useful SQL queries for analyzing relationships in your XML-to-SQLite database.

## Basic Relationship Queries

### Find all relationships for a specific node
```sql
-- Outgoing relationships
SELECT target_node_id, reference_type, confidence
FROM cross_references
WHERE source_node_id = 'your_node_id';

-- Incoming relationships
SELECT source_node_id, reference_type, confidence
FROM cross_references
WHERE target_node_id = 'your_node_id';

-- All relationships (bidirectional)
SELECT
  CASE WHEN source_node_id = 'your_node_id' THEN target_node_id ELSE source_node_id END as related_node,
  reference_type,
  CASE WHEN source_node_id = 'your_node_id' THEN 'outgoing' ELSE 'incoming' END as direction,
  confidence
FROM cross_references
WHERE source_node_id = 'your_node_id' OR target_node_id = 'your_node_id';
```

### Find direct children of a node
```sql
SELECT target_node_id as child_id, n.node_type, n.content
FROM cross_references cr
JOIN nodes n ON cr.target_node_id = n.id
WHERE cr.source_node_id = 'parent_node_id'
  AND cr.reference_type = 'parent_child';
```

### Find all siblings of a node
```sql
SELECT target_node_id as sibling_id, n.node_type, n.content
FROM cross_references cr
JOIN nodes n ON cr.target_node_id = n.id
WHERE cr.source_node_id = 'your_node_id'
  AND cr.reference_type = 'sibling';
```

## Hierarchical Queries

### Find all ancestors of a node (recursive CTE)
```sql
WITH RECURSIVE ancestors(descendant_id, ancestor_id, depth, path) AS (
  -- Base case: direct parent
  SELECT
    target_node_id as descendant_id,
    source_node_id as ancestor_id,
    1 as depth,
    source_node_id as path
  FROM cross_references
  WHERE target_node_id = 'your_node_id'
    AND reference_type = 'parent_child'

  UNION ALL

  -- Recursive case: parent's ancestors
  SELECT
    a.descendant_id,
    cr.source_node_id as ancestor_id,
    a.depth + 1,
    cr.source_node_id || ' -> ' || a.path
  FROM ancestors a
  JOIN cross_references cr ON a.ancestor_id = cr.target_node_id
  WHERE cr.reference_type = 'parent_child' AND a.depth < 10
)
SELECT ancestor_id, depth, path FROM ancestors ORDER BY depth;
```

### Find all descendants of a node
```sql
WITH RECURSIVE descendants(ancestor_id, descendant_id, depth, path) AS (
  -- Base case: direct children
  SELECT
    source_node_id as ancestor_id,
    target_node_id as descendant_id,
    1 as depth,
    target_node_id as path
  FROM cross_references
  WHERE source_node_id = 'your_node_id'
    AND reference_type = 'parent_child'

  UNION ALL

  -- Recursive case: children's descendants
  SELECT
    d.ancestor_id,
    cr.target_node_id as descendant_id,
    d.depth + 1,
    d.path || ' -> ' || cr.target_node_id
  FROM descendants d
  JOIN cross_references cr ON d.descendant_id = cr.source_node_id
  WHERE cr.reference_type = 'parent_child' AND d.depth < 10
)
SELECT descendant_id, depth, path FROM descendants ORDER BY depth;
```

## Analytical Queries

### Relationship summary by type
```sql
SELECT
  reference_type,
  COUNT(*) as total_count,
  AVG(confidence) as avg_confidence,
  MIN(confidence) as min_confidence,
  MAX(confidence) as max_confidence,
  COUNT(DISTINCT source_node_id) as unique_sources,
  COUNT(DISTINCT target_node_id) as unique_targets
FROM cross_references
GROUP BY reference_type
ORDER BY total_count DESC;
```

### Node relationship counts
```sql
SELECT
  n.id,
  n.node_type,
  COALESCE(outgoing.count, 0) as outgoing_relationships,
  COALESCE(incoming.count, 0) as incoming_relationships,
  COALESCE(outgoing.count, 0) + COALESCE(incoming.count, 0) as total_relationships
FROM nodes n
LEFT JOIN (
  SELECT source_node_id, COUNT(*) as count
  FROM cross_references
  GROUP BY source_node_id
) outgoing ON n.id = outgoing.source_node_id
LEFT JOIN (
  SELECT target_node_id, COUNT(*) as count
  FROM cross_references
  GROUP BY target_node_id
) incoming ON n.id = incoming.target_node_id
ORDER BY total_relationships DESC;
```

### Most connected nodes
```sql
SELECT
  n.id,
  n.node_type,
  n.content,
  COUNT(cr.id) as connection_count
FROM nodes n
JOIN cross_references cr ON n.id = cr.source_node_id OR n.id = cr.target_node_id
GROUP BY n.id, n.node_type, n.content
ORDER BY connection_count DESC
LIMIT 10;
```

### Bidirectional relationships
```sql
SELECT
  cr1.source_node_id as node1_id,
  cr1.target_node_id as node2_id,
  cr1.reference_type,
  cr1.confidence,
  cr1.attribute_name,
  cr2.id IS NOT NULL as is_bidirectional
FROM cross_references cr1
LEFT JOIN cross_references cr2 ON (
  cr1.source_node_id = cr2.target_node_id
  AND cr1.target_node_id = cr2.source_node_id
  AND cr1.reference_type = cr2.reference_type
)
WHERE cr2.id IS NOT NULL;  -- Only show bidirectional relationships
```

## Attribute Reference Queries

### Find all nodes that reference a specific node
```sql
SELECT
  source_node_id,
  attribute_name,
  confidence,
  n.node_type,
  n.content
FROM cross_references cr
JOIN nodes n ON cr.source_node_id = n.id
WHERE cr.target_node_id = 'referenced_node_id'
  AND cr.reference_type = 'attribute_reference'
ORDER BY confidence DESC;
```

### Find broken references (references to non-existent nodes)
```sql
SELECT DISTINCT cr.target_node_id as missing_node_id
FROM cross_references cr
LEFT JOIN nodes n ON cr.target_node_id = n.id
WHERE n.id IS NULL;
```

## Performance Tips

1. **Use indexes**: The migration creates indexes on common query patterns
2. **Limit recursion depth**: Use `depth < 10` in recursive CTEs to prevent infinite loops
3. **Filter early**: Use WHERE clauses to limit result sets before JOINs
4. **Consider confidence**: Filter by confidence thresholds for higher-quality relationships

## Creating Views

If you frequently use certain queries, you can create views:

```sql
-- Create a view for hierarchical paths
CREATE VIEW hierarchical_paths AS
WITH RECURSIVE ancestor_chain(descendant_id, ancestor_id, depth, path) AS (
  SELECT
    target_node_id as descendant_id,
    source_node_id as ancestor_id,
    1 as depth,
    source_node_id || ' -> ' || target_node_id as path
  FROM cross_references
  WHERE reference_type = 'parent_child'

  UNION ALL

  SELECT
    ac.descendant_id,
    cr.source_node_id as ancestor_id,
    ac.depth + 1,
    cr.source_node_id || ' -> ' || ac.path as path
  FROM ancestor_chain ac
  JOIN cross_references cr ON ac.ancestor_id = cr.target_node_id
  WHERE cr.reference_type = 'parent_child' AND ac.depth < 10
)
SELECT * FROM ancestor_chain;

-- Use the view
SELECT * FROM hierarchical_paths WHERE descendant_id = 'your_node_id';
```
