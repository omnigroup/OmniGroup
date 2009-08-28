class String
  # For turning entity names into relationship names, for example.
  def downcase_first
    result = self.dup
    result[0..0] = result[0..0].downcase
    result
  end
end
