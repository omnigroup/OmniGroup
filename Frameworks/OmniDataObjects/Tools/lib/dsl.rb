module OmniDataObjects
  @@CurrentModel = nil
  @@CurrentEntity = nil
  @@Inheriting = false
  
  def model(name, options = {})
    fail "Cannot nest models" if @@CurrentModel
    begin
      STDERR.print "Pushing model '#{name}'\n" if Options.debug
      @@CurrentModel = Model.new(name, options)
      yield @@CurrentModel
      @@CurrentModel.process
      @@CurrentModel.validate
      @@CurrentModel.emit
    ensure
      @@CurrentModel = nil
      STDERR.print "Popped model\n" if Options.debug
    end
  end
  
  
  def entity(name, options = {})
    fail "Cannot nest entities" if @@CurrentEntity
    fail "Cannot have an entity outside a model" unless @@CurrentModel
    begin
      STDERR.print "  Pushing entity '#{name}'\n" if Options.debug
      @@CurrentEntity = Entity.new(@@CurrentModel, name, options)
      yield @@CurrentEntity
      @@CurrentModel.add_entity(@@CurrentEntity) if !@@CurrentEntity.abstract
      return @@CurrentEntity
    ensure
      @@CurrentEntity = nil
      STDERR.print "  Popped entity\n" if Options.debug
    end
  end
  
  def inherit(key)
    fail "Cannot inherit outside an entity" unless @@CurrentEntity

    STDERR.print "    Inheriting via #{key} for #{@@CurrentEntity.name}\n" if Options.debug
    # Can nest inheritance.  Also, this provides a limited way to nest entities.  We pop the current entity off and temporarily define an abstract entity.
    old_inherit = @@Inheriting
    @@Inheriting = nil # temporary until we are sure the inherited entity is created!
    child_entity = @@CurrentEntity
    @@CurrentEntity = nil
    begin
      @@Inheriting = @@CurrentModel.add_inherit(key) # This will create an abstract entity
      @@CurrentEntity = child_entity
      child_entity.send(key)
    ensure
      @@Inheriting = old_inherit
      @@CurrentEntity = child_entity
    end
  end
  
  def attribute(name, type, options = {})
    fail "Attribute '#{name}' must be defined inside an entity" unless @@CurrentEntity
    STDERR.print "    Adding attribute '#{name}'\n" if Options.debug
    if @@Inheriting
      options = options.dup
      options[:inherited_from] = @@Inheriting
    end
    @@CurrentEntity.add_property(Attribute.new(@@CurrentEntity, name, type, options))
  end
  
  def relationship(name, target, inverse, options = {})
    fail "Relationship '#{name}' must be defined inside an entity" unless @@CurrentEntity
    STDERR.print "    Adding relationship #{target}.#{name}\n" if Options.debug
    if @@Inheriting
      options = options.dup
      options[:inherited_from] = @@Inheriting
    end
    @@CurrentEntity.add_property(Relationship.new(@@CurrentEntity, name, target, inverse, options))
  end
end
