#!/usr/bin/ruby

SLOT_COUNT = ENV["SLOT_COUNT"] || 64
output_path = ENV["SCRIPT_OUTPUT_FILE_0"] || fail("SCRIPT_OUTPUT_FILE_0 not set in environment")

# Build into a buffer and only write the output if different
buffer = "#define ODOObjectIndexedAccessorCount (#{SLOT_COUNT})\n"
for slot in 0..SLOT_COUNT-1
  # emit the functions
  buffer << <<-EOS
  static id _ODOObjectAttributeGetterAtIndex_#{slot}(ODOObject *self, SEL _cmd) { return _ODOObjectAttributeGetterAtIndex(self, #{slot}); }
  static BOOL _ODOObjectBoolAttributeGetterAtIndex_#{slot}(ODOObject *self, NSUInteger snapshotIndex) { return _ODOObjectBoolAttributeGetterAtIndex(self, #{slot}); }
  static int16_t _ODOObjectInt16AttributeGetterAtIndex_#{slot}(ODOObject *self, NSUInteger snapshotIndex) { return _ODOObjectInt16AttributeGetterAtIndex(self, #{slot}); }
  static int32_t _ODOObjectInt32AttributeGetterAtIndex_#{slot}(ODOObject *self, NSUInteger snapshotIndex) { return _ODOObjectInt32AttributeGetterAtIndex(self, #{slot}); }
  static int64_t _ODOObjectInt64AttributeGetterAtIndex_#{slot}(ODOObject *self, NSUInteger snapshotIndex) { return _ODOObjectInt64AttributeGetterAtIndex(self, #{slot}); }
  static float _ODOObjectFloat32AttributeGetterAtIndex_#{slot}(ODOObject *self, NSUInteger snapshotIndex) { return _ODOObjectFloat32AttributeGetterAtIndex(self, #{slot}); }
  static double _ODOObjectFloat64AttributeGetterAtIndex_#{slot}(ODOObject *self, NSUInteger snapshotIndex) { return _ODOObjectFloat64AttributeGetterAtIndex(self, #{slot}); }
  static id _ODOObjectToOneRelationshipGetterAtIndex_#{slot}(ODOObject *self, SEL _cmd) { return _ODOObjectToOneRelationshipGetterAtIndex(self, #{slot}); }
  static id _ODOObjectToManyRelationshipGetterAtIndex_#{slot}(ODOObject *self, SEL _cmd) { return _ODOObjectToManyRelationshipGetterAtIndex(self, #{slot}); }
  EOS
end

buffer << <<-EOS
typedef struct {
  struct {
    IMP get;
    IMP get_bool;
    IMP get_int16;
    IMP get_int32;
    IMP get_int64;
    IMP get_float32;
    IMP get_float64;
  } attribute;
  struct {
    IMP get;
  } to_one;
  struct {
    IMP get;
  } to_many;
} ODOAccessors;
static const ODOAccessors IndexedAccessors[ODOObjectIndexedAccessorCount] = {
EOS

for slot in 0..SLOT_COUNT-1
    buffer << "    {{(IMP)_ODOObjectAttributeGetterAtIndex_#{slot}, (IMP)_ODOObjectBoolAttributeGetterAtIndex_#{slot}, (IMP)_ODOObjectInt16AttributeGetterAtIndex_#{slot}, (IMP)_ODOObjectInt32AttributeGetterAtIndex_#{slot}, (IMP)_ODOObjectInt64AttributeGetterAtIndex_#{slot}, (IMP)_ODOObjectFloat32AttributeGetterAtIndex_#{slot}, (IMP)_ODOObjectFloat64AttributeGetterAtIndex_#{slot},
}, {(IMP)_ODOObjectToOneRelationshipGetterAtIndex_#{slot}}, {(IMP)_ODOObjectToManyRelationshipGetterAtIndex_#{slot}}},\n"
end
buffer << "};\n"

STDERR.print "writing #{output_path}...\n"
if !File.exists?(output_path) || File.read(output_path) != buffer
  File.open(output_path, "w") do |f|
    f << buffer
  end
end
