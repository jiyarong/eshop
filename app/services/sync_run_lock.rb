require "zlib"

class SyncRunLock
  def self.with_lock(name, wait:, logger: Rails.logger)
    key = lock_key(name)
    connection = ActiveRecord::Base.connection
    locked = wait ? blocking_lock(connection, key) : try_lock(connection, key)

    unless locked
      logger.info("[SyncRunLock] skipped name=#{name} reason=lock_busy")
      return { skipped: true, reason: "lock_busy" }
    end

    logger.info("[SyncRunLock] acquired name=#{name} wait=#{wait}")
    yield
  ensure
    if locked
      connection.select_value(ActiveRecord::Base.sanitize_sql_array(["SELECT pg_advisory_unlock(?)", key]))
      logger.info("[SyncRunLock] released name=#{name}")
    end
  end

  def self.lock_key(name)
    Zlib.crc32(name.to_s)
  end

  def self.blocking_lock(connection, key)
    connection.execute(ActiveRecord::Base.sanitize_sql_array(["SELECT pg_advisory_lock(?)", key]))
    true
  end
  private_class_method :blocking_lock

  def self.try_lock(connection, key)
    connection.select_value(ActiveRecord::Base.sanitize_sql_array(["SELECT pg_try_advisory_lock(?)", key]))
  end
  private_class_method :try_lock
end
