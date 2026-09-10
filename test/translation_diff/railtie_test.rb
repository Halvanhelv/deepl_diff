require "test_helper"
require "rake"

begin
  require "translation_diff/railtie"
  RAILTIE_AVAILABLE = true
rescue LoadError
  RAILTIE_AVAILABLE = false
end

if RAILTIE_AVAILABLE
  class RailtieTest < Minitest::Test
    def setup
      @previous_application = Rake.application
      Rake.application = Rake::Application.new
    end

    def teardown
      Rake.application = @previous_application
    end

    # This is what Rails calls when an application runs `rake -T` or `rails runner`, never the gem's own Rakefile.
    def test_registers_the_prune_task_from_the_gems_own_file
      TranslationDiff::Railtie.instance.send(:run_tasks_blocks, nil)

      assert Rake::Task.task_defined?("translation_diff:prune")
    end

    # Without this, the task prunes whatever the default configuration resolves to, not the host application's.
    def test_the_registered_task_depends_on_environment
      TranslationDiff::Railtie.instance.send(:run_tasks_blocks, nil)

      assert_includes Rake::Task["translation_diff:prune"].prerequisites, "environment"
    end
  end
else
  class RailtieTest < Minitest::Test
    def test_rails_railtie_is_unavailable
      skip "Rails::Railtie could not be loaded; the railtie suite is skipped"
    end
  end
end
