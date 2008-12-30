#!/usr/bin/ruby

SLOT_COUNT = ENV["SLOT_COUNT"] || 64
output_path = ENV["SCRIPT_OUTPUT_FILE_0"] || fail("SCRIPT_OUTPUT_FILE_0 not set in environment")

# Build into a buffer and only write the output if different
buffer = "#define ODOObjectIndexedAccessorCount (#{SLOT_COUNT})\n"
for slot in 0..SLOT_COUNT-1
  # emit the functions
  buffer << <<-EOS
  static id _ODOObjectAttributeGetterAtIndex_#{slot}(ODOObject *self, SEL _cmd) { return _ODOObjectAttributeGetterAtIndex(self, #{slot}); }
  static id _ODOObjectToOneRelationshipGetterAtIndex_#{slot}(ODOObject *self, SEL _cmd) { return _ODOObjectToOneRelationshipGetterAtIndex(self, #{slot}); }
  static id _ODOObjectToManyRelationshipGetterAtIndex_#{slot}(ODOObject *self, SEL _cmd) { return _ODOObjectToManyRelationshipGetterAtIndex(self, #{slot}); }
  EOS
end

buffer << <<-EOS
typedef struct {
  struct {
    ODOPropertyGetter get;
  } attribute;
  struct {
    ODOPropertyGetter get;
  } to_one;
  struct {
    ODOPropertyGetter get;
  } to_many;
} ODOAccessors;
const ODOAccessors IndexedAccessors[ODOObjectIndexedAccessorCount] = {
EOS

for slot in 0..SLOT_COUNT-1
  buffer << "    {{_ODOObjectAttributeGetterAtIndex_#{slot}}, {_ODOObjectToOneRelationshipGetterAtIndex_#{slot}}, {_ODOObjectToManyRelationshipGetterAtIndex_#{slot}}},\n"
end
buffer << "};\n"

STDERR.print "writing #{output_path}...\n"
if !File.exists?(output_path) || File.read(output_path) != buffer
  File.open(output_path, "w") do |f|
    f << buffer
  end
end
