class Player
  ALL_DIRS = [:left, :forward, :right, :backward]
  MAX_HEALTH = 20
  ATTACK_POWER = 5
  ENEMY_DMG = 3
  MAX_BLOWS = 5

  def initialize
    @captives = nil
    @captives_amount = nil
    @bound_amount = 0
    @bound_dirs = []
    @bound_damage = 0
    @evacuation_dir = nil
  end

  def play_turn(warrior)
    units = detect_units(warrior)
    @captives = units.select{ |space| space.respond_to?(:captive?) && space.captive? } if @captives.nil?
    @captives_amount = @captives.size if @captives_amount.nil?

    if @captive_dir
      @captives_amount -= 1 if warrior.feel(@captive_dir).empty?
      @bound_amount -= 1 if warrior.feel(@captive_dir).enemy?
      @bound_damage = 0 unless @bound_amount
      @captive_dir = nil
    end

    if units.empty? && !@evacuation_dir
        get_me_out_of_here(warrior)   # no one left
    else
      enemies = get_nearby_units(warrior, :enemy?)
      ticking = units.select{ |space| space.respond_to?(:ticking?) && space.ticking? }  # lets check if enemy can tick ;)
      if ticking.empty?
        clean_em_up(warrior, units, enemies, units)
      else  # bomb!!!11
        clean_em_up(warrior, ticking, enemies, units, :hurry)
      end
    end
  end

  def clean_em_up(warrior, target_units, enemies, all_units, hurry = false)
    min_health = [hurry ? MAX_HEALTH/2 : MAX_HEALTH, 1 + damage_estimate(all_units) + @bound_damage].min
    puts "health=#{warrior.health} min_health=#{min_health}: damage_estimate=#{damage_estimate(all_units)} @bound_damage=#{@bound_damage}"

    # handle surrunding
    if enemies.size > 1
      target_dir = warrior.respond_to?(:direction_of) ? warrior.direction_of(target_units[0]) : :none
      enemy_dir = enemies.find { |dir| dir != target_dir }  # out-of-way enemy
      return bind_enemy(warrior, enemy_dir) if enemy_dir
    end

    # am I dying?
    return evacuate(warrior, enemies) if !hurry && need_evacuation?(warrior, enemies)

    # am I bleeding in a safe place?
    return warrior.rest! if need_a_rest(warrior, min_health, enemies, all_units, hurry)

    # look around for enemies
    return self if handle_units(warrior, target_units, :enemy?) do |space, dir|
      # TODO find direction with the most amount of enemies
      attack(warrior, dir)
    end
    return attack(warrior, @bound_dirs.shift) unless @bound_dirs.empty? || hurry

    # look around for victims
    return self if handle_units(warrior, target_units, :captive?) do |space, dir|
      warrior.rescue!(dir)
      @captives.delete(space) # doesn't work ;(
      @captive_dir = dir
    end

    # go further
    select_walking_direction(warrior, target_units) do |dir|
      if (!warrior.feel(dir).empty? || warrior.feel(dir).stairs?) && !warrior.feel(dir).enemy?
        dir = detour_heuristics(warrior, dir)
      end
      if warrior.feel(dir).empty?
        move(warrior, dir)
        break :done
      end
    end
  end

  def attack(warrior, dir)
    captive_distance = @captives.map{ |space| warrior.distance_of(space) }.min || raise rescue 10
    # TODO detonate the last unit if enough health
    if warrior.respond_to?(:look) && (warrior.look(dir).count{ |space| space.enemy? } > 1) && captive_distance > 2
      warrior.detonate!(dir)
    else
      warrior.attack!(dir)
    end
  end

  def need_a_rest(warrior, min_health, enemies, all_units, hurry)
    return false if warrior.health >= min_health || !enemies.empty?
    return true if @evacuation_dir
    return false if all_units.size == @captives_amount
    return false if (hurry || @bound_amount == 0) && (@bound_amount + @captives_amount == all_units.size)
    return true
  end

  def unit_damage(unit, priority)
    bonus = (priority == :first_strike) ? 1 : 0
    (unit.health.fdiv(ATTACK_POWER).ceil - bonus) * unit.attack_power
  end

  def damage_estimate(units)
    units.select{ |space| space.enemy? }.map{ |enemy| unit_damage(enemy.unit, :first_strike) }.reduce(:+) || 0
  end

  def select_walking_direction(warrior, units)
    if @evacuation_dir
      yield opposite_direction(@evacuation_dir)
      @evacuation_dir = nil
    elsif warrior.respond_to?(:direction_of)
      units.each do |space|
        return self if yield(warrior.direction_of(space)) == :done
      end
    else
      yield warrior.direction_of_stairs
    end
  end

  def handle_units(warrior, units, check)
    if warrior.respond_to?(:direction_of)
      units.each do |space|
        dir = warrior.direction_of(space)
        if warrior.feel(dir).send(check)
          yield space, dir
          return true
        end
      end
    else
      ALL_DIRS.each do |dir|
        if warrior.feel(dir).send(check)
          yield nil, dir
          return true
        end
      end
    end
    return false
  end

  def get_me_out_of_here(warrior)
    dir = warrior.direction_of_stairs
    move(warrior, if warrior.feel(dir).empty? then dir else detour_heuristics(warrior, dir) end)
  end

  def detect_units(warrior)
    if warrior.respond_to?(:listen)
      warrior.listen
    else
      get_nearby_units(warrior, :enemy?) + get_nearby_units(warrior, :captive?)
    end
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
    # ... or try opposite route...
    if !warrior.feel(detour).empty? || !warrior.feel(detour).stairs? || !warrior.feel(detour).wall?
      detour = opposite_direction(detour)
    end
    return detour
  end

  def opposite_direction(dir)
    { :left     => :right,
      :forward  => :backward,
      :right    => :left,
      :backward => :forward
    }[dir]
  end

  def bind_enemy(warrior, dir)
    @bound_amount += 1
    @bound_dirs << dir
    @bound_damage = unit_damage(warrior.feel(dir).unit, :normal_strike)
    warrior.bind!(dir)
  end

  def need_evacuation?(warrior, enemies)
    required_health = 1 + (enemies.map{ |dir| warrior.feel(dir).unit.attack_power }.reduce(:+) || 0)
    return warrior.health < required_health && ALL_DIRS.any? { |d| warrior.feel(d).empty? }
  end

  def evacuate(warrior, enemies)
    if warrior.respond_to?(:bind!) && enemies.size == 1
      bind_enemy(warrior, enemies[0])   # don't evacuate if enemy can be captured
    else
      @evacuation_dir = ALL_DIRS.find { |d| warrior.feel(d).empty? && !warrior.feel(d).stairs? } || :forward
      move(warrior, @evacuation_dir)
    end
  end

  def move(warrior, dir)
    @bound_dirs = []  # TODO floor map
    warrior.walk!(dir)
  end
end
