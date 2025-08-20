# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

desc 'Run RuboCop'
task :rubocop do
  sh 'rubocop --parallel'
end

desc 'Run all tests'
task default: :test

desc 'Run RuboCop and tests'
task ci: %i[rubocop test]
