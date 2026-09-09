require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  # The dependencies are noisy under -w; their warnings drown out our own.
  t.warning = false
end

task default: :test
