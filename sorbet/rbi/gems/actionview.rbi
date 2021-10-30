# This file is autogenerated. Do not edit it by hand. Regenerate it with:
#   srb rbi gems

# typed: ignore
#
# If you would like to make changes to this file, great! Please create the gem's shim here:
#
#   https://github.com/sorbet/sorbet-typed/new/master?filename=lib/actionview/all/actionview.rbi
#
# actionview-6.1.4.1

module ActionView
  def self.eager_load!; end
  def self.gem_version; end
  def self.version; end
  extend ActiveSupport::Autoload
end
module ActionView::VERSION
end
class ActionView::Railtie < Rails::Engine
end
module ActionView::ViewPaths
  def _prefixes; end
  def any_templates?(**, &&); end
  def append_view_path(path); end
  def details_for_lookup; end
  def formats(**, &&); end
  def formats=(arg); end
  def locale(**, &&); end
  def locale=(arg); end
  def lookup_context; end
  def prepend_view_path(path); end
  def self.all_view_paths; end
  def self.get_view_paths(klass); end
  def self.set_view_paths(klass, paths); end
  def template_exists?(**, &&); end
  def view_paths(**, &&); end
  extend ActiveSupport::Concern
end
module ActionView::ViewPaths::ClassMethods
  def _prefixes; end
  def _view_paths; end
  def _view_paths=(paths); end
  def append_view_path(path); end
  def local_prefixes; end
  def prepend_view_path(path); end
  def view_paths; end
  def view_paths=(paths); end
end
class ActionView::I18nProxy < I18n::Config
  def initialize(original_config, lookup_context); end
  def locale; end
  def locale=(value); end
  def lookup_context; end
  def original_config; end
end
module ActionView::Rendering
  def _normalize_args(action = nil, options = nil); end
  def _normalize_options(options); end
  def _process_format(format); end
  def _render_template(options); end
  def initialize; end
  def process(*arg0); end
  def render_to_body(options = nil); end
  def rendered_format; end
  def view_context; end
  def view_context_class; end
  def view_renderer; end
  extend ActiveSupport::Concern
  include ActionView::ViewPaths
end
module ActionView::Rendering::ClassMethods
  def _helpers; end
  def _routes; end
  def build_view_context_class(klass, supports_path, routes, helpers); end
  def view_context_class; end
end
module ActionView::Layouts
  def _conditional_layout?; end
  def _default_layout(lookup_context, formats, require_layout = nil); end
  def _include_layout?(options); end
  def _layout(*arg0); end
  def _layout_conditions(**, &&); end
  def _layout_for_option(name); end
  def _normalize_layout(value); end
  def _normalize_options(options); end
  def action_has_layout=(arg0); end
  def action_has_layout?; end
  def initialize(*arg0); end
  extend ActiveSupport::Concern
  include ActionView::Rendering
end
module ActionView::Layouts::ClassMethods
  def _implied_layout_name; end
  def _write_layout_method; end
  def inherited(klass); end
  def layout(layout, conditions = nil); end
end
module ActionView::Layouts::ClassMethods::LayoutConditions
  def _conditional_layout?; end
end
class ActionView::PathSet
  def +(array); end
  def <<(*args); end
  def [](**, &&); end
  def _find_all(path, prefixes, args); end
  def compact; end
  def concat(*args); end
  def each(**, &&); end
  def exists?(path, prefixes, *args); end
  def find(*args); end
  def find_all(path, prefixes = nil, *args); end
  def find_all_with_query(query); end
  def include?(**, &&); end
  def initialize(paths = nil); end
  def initialize_copy(other); end
  def insert(*args); end
  def paths; end
  def pop(**, &&); end
  def push(*args); end
  def size(**, &&); end
  def to_ary; end
  def typecast(paths); end
  def unshift(*args); end
  include Enumerable
end
class ActionView::Template
  def compile!(view); end
  def compile(mod); end
  def encode!; end
  def format; end
  def handle_render_error(view, e); end
  def handler; end
  def identifier; end
  def identifier_method_name; end
  def initialize(source, identifier, handler, locals:, format: nil, variant: nil, virtual_path: nil); end
  def inspect; end
  def instrument(action, &block); end
  def instrument_payload; end
  def instrument_render_template(&block); end
  def locals; end
  def locals_code; end
  def marshal_dump; end
  def marshal_load(array); end
  def method_name; end
  def render(view, locals, buffer = nil, add_to_stack: nil, &block); end
  def short_identifier; end
  def source; end
  def supports_streaming?; end
  def type; end
  def variable; end
  def variant; end
  def virtual_path; end
  extend ActionView::Template::Handlers
  extend ActiveSupport::Autoload
end
module ActionView::Template::Handlers
  def handler_for_extension(extension); end
  def register_default_template_handler(extension, klass); end
  def register_template_handler(*extensions, handler); end
  def registered_template_handler(extension); end
  def self.extended(base); end
  def self.extensions; end
  def template_handler_extensions; end
  def unregister_template_handler(*extensions); end
end
class ActionView::Template::Handlers::Raw
  def call(template, source); end
end
class ActionView::Template::Handlers::ERB
  def call(template, source); end
  def erb_implementation; end
  def erb_implementation=(arg0); end
  def erb_implementation?; end
  def erb_trim_mode; end
  def erb_trim_mode=(arg0); end
  def erb_trim_mode?; end
  def escape_ignore_list; end
  def escape_ignore_list=(arg0); end
  def escape_ignore_list?; end
  def handles_encoding?; end
  def self.call(template, source); end
  def self.erb_implementation; end
  def self.erb_implementation=(value); end
  def self.erb_implementation?; end
  def self.erb_trim_mode; end
  def self.erb_trim_mode=(value); end
  def self.erb_trim_mode?; end
  def self.escape_ignore_list; end
  def self.escape_ignore_list=(value); end
  def self.escape_ignore_list?; end
  def supports_streaming?; end
  def valid_encoding(string, encoding); end
end
class ActionView::Template::Handlers::ERB::Erubi < Erubi::Engine
  def add_code(code); end
  def add_expression(indicator, code); end
  def add_postamble(_); end
  def add_text(text); end
  def evaluate(action_view_erb_handler_context); end
  def flush_newline_if_pending(src); end
  def initialize(input, properties = nil); end
end
class ActionView::Template::Handlers::Html < ActionView::Template::Handlers::Raw
  def call(template, source); end
end
class ActionView::Template::Handlers::Builder
  def call(template, source); end
  def default_format; end
  def default_format=(arg0); end
  def default_format?; end
  def require_engine; end
  def self.default_format; end
  def self.default_format=(value); end
  def self.default_format?; end
end
class ActionView::Resolver
  def _find_all(name, prefix, partial, details, key, locals); end
  def cached(key, path_info, details, locals); end
  def caching; end
  def caching=(val); end
  def caching?(**, &&); end
  def clear_cache; end
  def find_all(name, prefix = nil, partial = nil, details = nil, key = nil, locals = nil); end
  def find_all_with_query(query); end
  def find_templates(name, prefix, partial, details, locals = nil); end
  def initialize; end
  def self.caching; end
  def self.caching=(val); end
  def self.caching?; end
end
class ActionView::Resolver::Path
  def initialize(name, prefix, partial, virtual); end
  def name; end
  def partial; end
  def partial?; end
  def prefix; end
  def self.build(name, prefix, partial); end
  def to_s; end
  def to_str; end
  def virtual; end
end
class ActionView::Resolver::PathParser
  def build_path_regex; end
  def parse(path); end
end
class ActionView::Resolver::Cache
  def cache(key, name, prefix, partial, locals); end
  def cache_query(query); end
  def canonical_no_templates(templates); end
  def clear; end
  def initialize; end
  def inspect; end
  def size; end
end
class ActionView::Resolver::Cache::SmallCache < Concurrent::Map
  def initialize(options = nil); end
end
class ActionView::PathResolver < ActionView::Resolver
  def _find_all(name, prefix, partial, details, key, locals); end
  def build_query(path, details); end
  def build_unbound_template(template, virtual_path); end
  def clear_cache; end
  def escape_entry(entry); end
  def extract_handler_and_format_and_variant(path); end
  def find_template_paths(query); end
  def find_template_paths_from_details(path, details); end
  def initialize; end
  def inside_path?(path, filename); end
  def query(path, details, formats, locals, cache:); end
  def reject_files_external_to_app(files); end
  def source_for_template(template); end
end
class ActionView::FileSystemResolver < ActionView::PathResolver
  def ==(resolver); end
  def eql?(resolver); end
  def initialize(path); end
  def path; end
  def to_path; end
  def to_s; end
end
class ActionView::OptimizedFileSystemResolver < ActionView::FileSystemResolver
  def build_regex(path, details); end
  def find_candidate_template_paths(path); end
  def find_template_paths_from_details(path, details); end
  def initialize(path); end
end
class ActionView::FallbackFileSystemResolver < ActionView::FileSystemResolver
  def build_unbound_template(template, _); end
  def reject_files_external_to_app(files); end
  def self.instances; end
  def self.new(*arg0); end
end
class ActiveSupport::TestCase < Minitest::Test
  include ActiveSupport::CurrentAttributes::TestHelper
end
class ActionController::Base < ActionController::Metal
  def _serialization_scope; end
  def _serialization_scope=(arg0); end
  def _serialization_scope?; end
  def namespace_for_serializer=(arg0); end
  def self._serialization_scope; end
  def self._serialization_scope=(value); end
  def self._serialization_scope?; end
  extend ActionController::Railties::Helpers
  extend ActionController::Serialization::ClassMethods
  extend ActiveRecord::Railties::ControllerRuntime::ClassMethods
  extend Anonymous_Module_7
  include ActionController::Renderers
  include ActionController::Serialization
  include ActionDispatch::Routing::RouteSet::MountedHelpers
  include ActionDispatch::Routing::UrlFor
  include ActiveRecord::Railties::ControllerRuntime
end
module Anonymous_Module_7
  def inherited(klass); end
end
class ActionController::API < ActionController::Metal
  def _serialization_scope; end
  def _serialization_scope=(arg0); end
  def _serialization_scope?; end
  def namespace_for_serializer=(arg0); end
  def self._serialization_scope; end
  def self._serialization_scope=(value); end
  def self._serialization_scope?; end
  extend ActionController::Railties::Helpers
  extend ActionController::Serialization::ClassMethods
  extend ActiveRecord::Railties::ControllerRuntime::ClassMethods
  extend Anonymous_Module_8
  include ActionController::Renderers
  include ActionController::Serialization
  include ActionDispatch::Routing::RouteSet::MountedHelpers
  include ActionDispatch::Routing::UrlFor
  include ActiveRecord::Railties::ControllerRuntime
end
module Anonymous_Module_8
  def inherited(klass); end
end
class ActiveSupport::Executor < ActiveSupport::ExecutionWrapper
  def self.__callbacks; end
end
class ActiveRecord::Base
  include GlobalID::Identification
end