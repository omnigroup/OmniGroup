module OmniDataObjects
  class SourceFilePair
    attr_reader :h, :m, :swift
    def initialize(h, m, swift = nil)
      @h = h
      @m = m
      @swift = swift
    end
  end
end
