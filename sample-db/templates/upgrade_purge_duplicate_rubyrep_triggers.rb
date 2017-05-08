# This script removes triggers that could cause issues with rubyrep.
# When tables are renamed, the rubyrep trigger should be removed and recreated.
# When they are not, it is possible to end up with multiple triggers on the renamed table.
# Both triggers will run, but the old one will insert pending changes for a table that no longer exists.
# When this happens with high-churn tables it can cause the replicate process to timeout.
#
# NOTE: modified from original purge_duplicate_rubyrep_triggers.rb for use with automated upgrade

require 'pg'

TRIGGER_QUERY = <<-SQL.freeze
SELECT relname, array_agg(tgname) AS triggers
FROM
  pg_trigger t JOIN
  pg_class c ON t.tgrelid = c.oid
WHERE
  t.tgname like 'rr%'
GROUP BY relname
SQL

def sql_array_to_ruby(sql_arr)
  # the array is returned like: "{value1,value2,value3}"
  # so we cut out the brackets and split on commas
  sql_arr[1..-2].split(",")
end

def drop_triggers(conn, table, triggers)
  triggers.each do |trigger|
    puts "Dropping trigger #{trigger} from table #{table}"
    conn.async_exec("DROP TRIGGER IF EXISTS #{trigger} ON #{table}")
    conn.async_exec("DROP FUNCTION IF EXISTS #{trigger}()")
  end
end

begin
  conn = PG.connect(:dbname => "vmdb_production")
rescue PG::Error => e
  puts e.message
  puts "Please run this script on the appliance where the database is running"
  exit
end

conn.async_exec(TRIGGER_QUERY).each do |tt|
  triggers = sql_array_to_ruby(tt["triggers"])
  table = tt["relname"]

  to_drop = triggers.reject { |t| t =~ /rr\d_#{table}/ }
  next if to_drop.empty?

  puts "Dropping trigger(s) on table #{table}"
  drop_triggers(conn, table, to_drop)
end
