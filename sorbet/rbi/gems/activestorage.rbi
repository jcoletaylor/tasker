# This file is autogenerated. Do not edit it by hand. Regenerate it with:
#   srb rbi gems

# typed: strict
#
# If you would like to make changes to this file, great! Please create the gem's shim here:
#
#   https://github.com/sorbet/sorbet-typed/new/master?filename=lib/activestorage/all/activestorage.rbi
#
# activestorage-6.1.4.1

module ActiveStorage
  def analyzers; end
  def analyzers=(val); end
  def binary_content_type; end
  def binary_content_type=(val); end
  def content_types_allowed_inline; end
  def content_types_allowed_inline=(val); end
  def content_types_to_serve_as_binary; end
  def content_types_to_serve_as_binary=(val); end
  def draw_routes; end
  def draw_routes=(val); end
  def logger; end
  def logger=(val); end
  def paths; end
  def paths=(val); end
  def previewers; end
  def previewers=(val); end
  def queues; end
  def queues=(val); end
  def replace_on_assign_to_many; end
  def replace_on_assign_to_many=(val); end
  def resolve_model_to_route; end
  def resolve_model_to_route=(val); end
  def routes_prefix; end
  def routes_prefix=(val); end
  def self.analyzers; end
  def self.analyzers=(val); end
  def self.binary_content_type; end
  def self.binary_content_type=(val); end
  def self.content_types_allowed_inline; end
  def self.content_types_allowed_inline=(val); end
  def self.content_types_to_serve_as_binary; end
  def self.content_types_to_serve_as_binary=(val); end
  def self.draw_routes; end
  def self.draw_routes=(val); end
  def self.gem_version; end
  def self.logger; end
  def self.logger=(val); end
  def self.paths; end
  def self.paths=(val); end
  def self.previewers; end
  def self.previewers=(val); end
  def self.queues; end
  def self.queues=(val); end
  def self.railtie_helpers_paths; end
  def self.railtie_namespace; end
  def self.railtie_routes_url_helpers(include_path_helpers = nil); end
  def self.replace_on_assign_to_many; end
  def self.replace_on_assign_to_many=(val); end
  def self.resolve_model_to_route; end
  def self.resolve_model_to_route=(val); end
  def self.routes_prefix; end
  def self.routes_prefix=(val); end
  def self.service_urls_expire_in; end
  def self.service_urls_expire_in=(val); end
  def self.table_name_prefix; end
  def self.track_variants; end
  def self.track_variants=(val); end
  def self.use_relative_model_naming?; end
  def self.variable_content_types; end
  def self.variable_content_types=(val); end
  def self.variant_processor; end
  def self.variant_processor=(val); end
  def self.verifier; end
  def self.verifier=(val); end
  def self.version; end
  def self.video_preview_arguments; end
  def self.video_preview_arguments=(val); end
  def self.web_image_content_types; end
  def self.web_image_content_types=(val); end
  def service_urls_expire_in; end
  def service_urls_expire_in=(val); end
  def track_variants; end
  def track_variants=(val); end
  def variable_content_types; end
  def variable_content_types=(val); end
  def variant_processor; end
  def variant_processor=(val); end
  def verifier; end
  def verifier=(val); end
  def video_preview_arguments; end
  def video_preview_arguments=(val); end
  def web_image_content_types; end
  def web_image_content_types=(val); end
  extend ActiveSupport::Autoload
end
module ActiveStorage::VERSION
end
class ActiveStorage::Error < StandardError
end
class ActiveStorage::InvariableError < ActiveStorage::Error
end
class ActiveStorage::UnpreviewableError < ActiveStorage::Error
end
class ActiveStorage::UnrepresentableError < ActiveStorage::Error
end
class ActiveStorage::IntegrityError < ActiveStorage::Error
end
class ActiveStorage::FileNotFoundError < ActiveStorage::Error
end
class ActiveStorage::PreviewError < ActiveStorage::Error
end
module ActiveStorage::Transformers
  extend ActiveSupport::Autoload
end
class ActiveStorage::Previewer
  def blob; end
  def capture(*argv, to:); end
  def download_blob_to_tempfile(&block); end
  def draw(*argv); end
  def initialize(blob); end
  def instrument(operation, payload = nil, &block); end
  def logger; end
  def open_tempfile; end
  def preview(**options); end
  def self.accept?(blob); end
  def tmpdir; end
end
class ActiveStorage::Previewer::PopplerPDFPreviewer < ActiveStorage::Previewer
  def draw_first_page_from(file, &block); end
  def preview(**options); end
  def self.accept?(blob); end
  def self.pdftoppm_exists?; end
  def self.pdftoppm_path; end
end
class ActiveStorage::Previewer::MuPDFPreviewer < ActiveStorage::Previewer
  def draw_first_page_from(file, &block); end
  def preview(**options); end
  def self.accept?(blob); end
  def self.mutool_exists?; end
  def self.mutool_path; end
end
class ActiveStorage::Previewer::VideoPreviewer < ActiveStorage::Previewer
  def draw_relevant_frame_from(file, &block); end
  def preview(**options); end
  def self.accept?(blob); end
  def self.ffmpeg_exists?; end
  def self.ffmpeg_path; end
end
class ActiveStorage::Analyzer
  def blob; end
  def download_blob_to_tempfile(&block); end
  def initialize(blob); end
  def logger; end
  def metadata; end
  def self.accept?(blob); end
  def self.analyze_later?; end
  def tmpdir; end
end
class ActiveStorage::Analyzer::ImageAnalyzer < ActiveStorage::Analyzer
  def metadata; end
  def read_image; end
  def rotated_image?(image); end
  def self.accept?(blob); end
end
class ActiveStorage::Analyzer::VideoAnalyzer < ActiveStorage::Analyzer
  def angle; end
  def computed_height; end
  def container; end
  def display_aspect_ratio; end
  def display_height_scale; end
  def duration; end
  def encoded_height; end
  def encoded_width; end
  def ffprobe_path; end
  def height; end
  def metadata; end
  def probe; end
  def probe_from(file); end
  def rotated?; end
  def self.accept?(blob); end
  def streams; end
  def tags; end
  def video_stream; end
  def width; end
end
class ActiveStorage::LogSubscriber < ActiveSupport::LogSubscriber
end
class ActiveStorage::Downloader
  def download(key, file); end
  def initialize(service); end
  def open(key, checksum:, name: nil, tmpdir: nil); end
  def open_tempfile(name, tmpdir = nil); end
  def service; end
  def verify_integrity_of(file, checksum:); end
end
class ActiveStorage::Service
  def content_disposition_with(filename:, type: nil); end
  def delete(key); end
  def delete_prefixed(prefix); end
  def download(key); end
  def download_chunk(key, range); end
  def exist?(key); end
  def headers_for_direct_upload(key, filename:, content_type:, content_length:, checksum:); end
  def instrument(operation, payload = nil, &block); end
  def name; end
  def name=(arg0); end
  def open(*args, **options, &block); end
  def private_url(key, expires_in:, filename:, disposition:, content_type:, **arg5); end
  def public?; end
  def public_url(key, **arg1); end
  def self.build(configurator:, name:, service: nil, **service_config); end
  def self.configure(service_name, configurations); end
  def service_name; end
  def update_metadata(key, **metadata); end
  def upload(key, io, checksum: nil, **options); end
  def url(key, **options); end
  def url_for_direct_upload(key, expires_in:, content_type:, content_length:, checksum:); end
  extend ActiveSupport::Autoload
end
class ActiveStorage::Service::Registry
  def configurations; end
  def configurator; end
  def fetch(name); end
  def initialize(configurations); end
  def services; end
end
module ActiveStorage::Reflection
end
class ActiveStorage::Reflection::HasOneAttachedReflection < ActiveRecord::Reflection::MacroReflection
  def macro; end
end
class ActiveStorage::Reflection::HasManyAttachedReflection < ActiveRecord::Reflection::MacroReflection
  def macro; end
end
module ActiveStorage::Reflection::ReflectionExtension
  def add_attachment_reflection(model, name, reflection); end
  def reflection_class_for(macro); end
end
module ActiveStorage::Reflection::ActiveRecordExtensions
  extend ActiveSupport::Concern
end
module ActiveStorage::Reflection::ActiveRecordExtensions::ClassMethods
  def reflect_on_all_attachments; end
  def reflect_on_attachment(attachment); end
end
class ActiveStorage::Engine < Rails::Engine
end
module ActiveStorage::Attached::Model
  def attachment_changes; end
  def changed_for_autosave?; end
  def initialize_dup(*arg0); end
  def reload(*arg0); end
  extend ActiveSupport::Concern
end
module ActiveStorage::Attached::Model::ClassMethods
  def has_many_attached(name, dependent: nil, service: nil, strict_loading: nil); end
  def has_one_attached(name, dependent: nil, service: nil, strict_loading: nil); end
  def validate_service_configuration(association_name, service); end
end
class ActiveStorage::Attached::One < ActiveStorage::Attached
  def attach(attachable); end
  def attached?; end
  def attachment; end
  def blank?; end
  def detach; end
  def method_missing(method, *args, &block); end
  def purge; end
  def purge_later; end
  def respond_to_missing?(name, include_private = nil); end
  def write_attachment(attachment); end
end
class ActiveStorage::Attached::Many < ActiveStorage::Attached
  def attach(*attachables); end
  def attached?; end
  def attachments; end
  def blobs; end
  def detach; end
  def method_missing(method, *args, &block); end
  def respond_to_missing?(name, include_private = nil); end
end
module ActiveStorage::Attached::Changes
  extend ActiveSupport::Autoload
end
class ActiveStorage::Attached
  def change; end
  def initialize(name, record); end
  def name; end
  def record; end
end
