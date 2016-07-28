class AddSourceToGames < ActiveRecord::Migration
  def up
		add_column :games, :source, :string
    change_column :games, :appid, :int, null: true
  end
  def down
  	remove_column :games, :source
    change_column :games, :appid, :int, null: false
  end
end
