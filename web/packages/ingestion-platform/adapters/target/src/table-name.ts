export interface QualifiedTableName {
  schema: string;
  table: string;
  displayName: string;
}

export function parseTableName(table: string): QualifiedTableName {
  const parts = table.split(".");
  const schema = parts.length === 2 ? parts[0] : "public";
  const tableName = parts.length === 2 ? parts[1] : parts[0];

  if (!schema || !tableName) {
    throw new Error(`Invalid target table name: ${table}`);
  }

  return {
    schema,
    table: tableName,
    displayName: parts.length === 2 ? `${schema}.${tableName}` : tableName
  };
}

export function quoteIdentifier(identifier: string): string {
  return `"${identifier.replaceAll('"', '""')}"`;
}
