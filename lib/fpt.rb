require 'sqlite3'
require 'json'
require 'date'

module Fpt

  class Db

    attr_reader :definition_ids, :definitions
    #noinspection RubyArgCount
    def initialize(params)
      if params[:file_path]
        @db = SQLite3::Database.new(params[:file_path])
      else
        @db = params[:db]
      end

      @definition_ids = []
      @definitions = []

      @db.execute("select ROWID,* from instances where type = 5") do |definition|
        @definition_ids << definition[0]
        fpt_definition = Definition.new(definition)
        @definitions << fpt_definition
      end


      @db.execute("select ROWID,* from instances") do |instance|
        Rails.logger.debug("INSTANCE: #{instance.join(", ")}")
      end
      @db.execute("select ROWID,* from indexes") do |instance|
        Rails.logger.debug("INDEX:\t #{instance.join(", ")}")
      end


    end

    def workout_entries(definition_id)
      entries = []
      @db.execute("select instance_id from indexes where path = 'workout_definition_id_#{definition_id}'") do |workout_entry_index|
        @db.execute("select ROWID,* from instances where ROWID = #{workout_entry_index[0]}") do |workout_entry|
          entries << Entry.new(workout_entry)
        end
      end
      entries
    end

    def definition_by_name name
      @definitions.each do |definition|
        if definition.data['workout_name'] == name
          return definition
        end
      end

      nil

    end
  end

  class Storable

    attr_reader :id, :type, :modified, :created, :data, :created_int, :modified_int

    def initialize(row=nil, map=nil)
      if row
        @id = row[0]
        @type = row[1]
        @created = DateTime.parse(row[2])
        @created_int = row[2]
        @modified = DateTime.parse(row[3])
        @modified_int = row[3]
        @data = JSON.parse(row[4])
      elsif map
        @id = map["id"]
        @type = map["type"]
        @created = DateTime.parse(map["created"])
        @modified = DateTime.parse(map["modified"])
        @data = map["data"]
      else
        raise ArgumentError.new("FptDefinition needs either row or map as an arg")
      end

    end
  end

  class Definition < Storable

  end

  class Entry < Storable

  end

  class Graph

    def initialize(fpt_model, fpt_db)
      @model = fpt_model
      @db = fpt_db
    end

    def graph_workout(workout_definition)

      model_id = workout_definition.data['workout_type']

      entries = @db.workout_entries(workout_definition.id)

      model = @model.by_id(model_id)

      x_value_name = model['x_value_name']
      x_data_set = []
      y_data_set = []
      data_set = []
      min_x_value = nil
      max_x_value = nil
      min_y_value = nil
      max_y_value = nil
      entries.each do |entry|
        x_val = entry.created.to_i
        x_data_set << x_val
        y_val = entry.data[x_value_name]
        y_data_set << y_val
        min_x_value = x_val if min_x_value.nil? || x_val < min_x_value
        max_x_value = x_val if max_x_value.nil? || x_val > max_x_value
        min_y_value = y_val if min_y_value.nil? || y_val < min_y_value
        max_y_value = y_val if max_y_value.nil? || y_val > max_y_value


        data_set << [entry.created.to_i, entry.data[x_value_name]]
      end

      data_set.sort! do |arr1, arr2|
        arr1[0] <=> arr2[0]
      end

#    gchart = GoogleChart::LineChart.new('320x200', workout_definition.data['workout_name'], true) do |lcxy|
#      lcxy.data nil, data_set, '0000ff'
#    end
#    gchart_line_url =Gchart.line_xy(:size => '200x300',
#            :title => ,
#            :bg => 'efefef',
#            :data => [x_data_set,y_data_set])
      x_data_set = []
      y_data_set = []

      relative_x_range = max_x_value-min_x_value

      num_labels = 6 # number of labels on the x-axis

      label_inc = relative_x_range / num_labels # increment for each label

      x_labels = []

      (0..num_labels).to_a.each do |i|
        rel_date = min_x_value + (label_inc * i)
        x_labels << Time.at(rel_date).strftime("%D")
      end

      data_set.each do |arr|
        x_val = arr[0]
        # x_val for gcharts is actually a percentage representation of where on the chart it will appear
        # 0  is all the way to the left, 100, is all the way to the right
        # this percentage should come from (max - min)/(y_actual - min)
        if x_val == min_x_value
          x_data_set << 0
        elsif x_val == max_x_value
          x_data_set << 100
        else
          x_data_set << (x_val.to_f - min_x_value)/(relative_x_range)*100
        end
        y_data_set << arr[1]
      end

      "http://chart.apis.google.com/chart?chs=600x325&chd=t:#{x_data_set.join(",")}|#{y_data_set.join(",")}&cht=lxy&chxt=x,y&chxr=1,#{min_y_value},#{max_y_value}&chxl=0:|#{x_labels.join("|")}"
    end
  end

  class Model
    def initialize(json)
      @models_by_name = JSON.parse(json)
      @models_by_id = {}
      @models_by_name.each_pair do |model_name, model_data|
        @models_by_id[model_data['id']] = model_name
      end

    end

    def by_id id
      name = @models_by_id[id]
      @models_by_name[name]
    end

    def by_name name
      @models_by_name[name]
    end
  end

  class Table
    def initialize fpt_model, fpt_db
      @db = fpt_db
      @model = fpt_model
    end

    def to_a(workout_definition)
      model_id = workout_definition.data['workout_type']

      entries = @db.workout_entries(workout_definition.id)

      model = @model.by_id(model_id)

      x_value_name = model['x_value_name']

      rows = []

      entries.each do |entry|
        rows << [entry.created, entry.data[x_value_name]]
      end

      rows

    end
  end

end