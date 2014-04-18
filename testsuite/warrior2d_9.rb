class Player
  ALL_DIRS = [:left, :forward, :right, :backward]
  MAX_HEALTH = 20
  ENEMY_DMG = 3

  def initialize
    @bound_amount = 0
  end

  def play_turn(warrior)
    units = warrior.listen
    @captives = units.select{ |space| space.captive? } unless @captives
    @captives_amount = @captives.size if @captives_amount.nil?

    if @captive_dir
      @captives_amount -= 1 if warrior.feel(@captive_dir).empty?
      @bound_amount -= 1 if warrior.feel(@captive_dir).enemy?
      @captive_dir = nil
    end

    if units.empty?
        get_me_out_of_here(warrior)   # no one left
    else
        enemies = get_nearby_units(warrior, :enemy?)
        ticking = units.select{ |space| space.ticking? }  # lets check if enemy can tickle ;)
        if ticking.empty?
          clean_em_up(warrior, units, enemies)
        else  # bomb!!!11
          clean_em_up(warrior, ticking, enemies, :hurry)
        end
    end
  end

  def clean_em_up(warrior, target_units, enemies, hurry = false)
    min_health = hurry ? MAX_HEALTH/2 : MAX_HEALTH

    # look around for victims
    if hurry || warrior.health >= min_health 
      return self if handle_units(warrior, target_units, :captive?) do |space, dir|
        warrior.rescue!(dir)
        @captives.delete(space) # doesn't work ;(
        @captive_dir = dir
      end
    end

    # handle surrunding
    if enemies.size > 1
      target_dir = warrior.direction_of(target_units[0])    # main target
      enemy_dir = enemies.find { |dir| dir != target_dir }  # out-of-way enemy
      if enemy_dir
        warrior.bind!(enemy_dir)
        @bound_amount += 1
        return self
      end
    end

    # am I dying?
    if !hurry && need_evacuation?(warrior, enemies)
      evacuate(warrior)
      return self
    end

    # am I bleeding in a safe place?
    if warrior.health < min_health && enemies.empty? && (target_units.size + enemies.size + @bound_amount > @captives_amount)
      warrior.rest!
      return self
    end

    # look around for enemies
    return self if handle_units(warrior, target_units, :enemy?) do |space, dir|
        captive_distance = @captives.map{ |space| warrior.distance_of(space) }.min rescue 10
        if (warrior.look(dir).count{ |space| space.enemy? } > 1) && captive_distance > 2
            warrior.detonate!(dir)
        else
            warrior.attack!(dir)
        end
    end

    # go further
    target_units.each do |space|
      dir = warrior.direction_of(space)
      if (!warrior.feel(dir).empty? || warrior.feel(dir).stairs?) && !warrior.feel(dir).enemy?
        dir = detour_heuristics(warrior, dir)
      end
      if warrior.feel(dir).empty?
        return warrior.walk!(dir)
      end

      # no easy way -- lets fight through ;)
    end
  end

  def handle_units(warrior, units, check)
    units.each do |space|
      dir = warrior.direction_of(space)
      if warrior.feel(dir).send(check)
        yield space, dir
        return true
      end
    end
    return false
  end

  def get_me_out_of_here(warrior)
    dir = warrior.direction_of_stairs
    warrior.walk!(if warrior.feel(dir).empty? then dir else detour_heuristics(warrior, dir) end)
  end

  def get_nearby_units(warrior, type_check)
    ALL_DIRS.select { |dir| warrior.feel(dir).send(type_check) }
  end

  def detour_heuristics(warrior, dir)
    detour = {
      :left     => :forward,
      :forward  => :right,
      :right    => :backward,
      :backward => :left
    }[dir]
    if !warrior.feel(detour).empty? || !warrior.feel(detour).stairs? || !warrior.feel(detour).wall? 
      detour = {
        :left     => :right,
        :forward  => :backward,
        :right    => :left,
        :backward => :forward
      }[detour]
    end
    return detour
  end

  def need_evacuation?(warrior, enemies)
    required = (enemies.size + 1) * ENEMY_DMG
    return enemies.size < 4 && warrior.health < required
  end

  def evacuate(warrior)
    dir = ALL_DIRS.find { |d| warrior.feel(d).empty? && !warrior.feel(d).stairs? } || :forward
    return warrior.walk!(dir)
  end
end
