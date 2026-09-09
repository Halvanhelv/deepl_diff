# Sets environment variables around a block and restores exactly what was there, including "was not set".
module EnvStub
  def with_env(values)
    original = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    apply_env(values)
    yield
  ensure
    apply_env(original)
  end

  private

  def apply_env(values)
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
