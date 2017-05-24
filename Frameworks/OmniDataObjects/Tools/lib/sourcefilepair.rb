module OmniDataObjects
  class SourceFilePair
    attr_reader :h, :m, :swift
    def initialize(h, m, swift = nil)
      @h = h
      @m = m
      @swift = swift
    end
    def br
      h.br
      m.br
    end
  end
end
