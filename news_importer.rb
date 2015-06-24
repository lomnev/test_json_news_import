require 'thor'
require 'yajl'
require 'sqlite3'

class NewsImporter < Thor

  DB_FILE = 'news.sqlite'

  class_option :only_active_cats, desc: 'Only active categories', aliases: '--ac', type: :boolean, default: false
  class_option :only_active_news, desc: 'Only active news', aliases: '--an', type: :boolean, default: false

  desc 'import FILE_NAME', 'imports news from FILE_NAME'

  def import(file_name)
    additional_initialize
    # получим hash из .json файла
    begin
      json = get_json(file_name)
      hash = get_parsed_hash(json)
    rescue Exception => e
      puts "Ошибка при попытке получения или разбора JSON - #{e.message}"
      Process.exit!
    end
    # импортируем категории
    hash.each do |root_category|
      import_one_category(root_category)
    end
    show_report
  end

  protected

  def additional_initialize
    begin
      init_database # @db
    rescue Exception => e
      puts "Ошибка при инициализации базы данных - #{e.message}"
      Process.exit!
    end
    @count_category_success = 0
    @count_news_success = 0
  end

  def init_database
    @db = SQLite3::Database.new DB_FILE
    @db.execute <<-SQL
              CREATE TABLE IF NOT EXISTS category (
                  id          INTEGER UNIQUE,
                  name        VARCHAR UNIQUE
              );
    SQL
    @db.execute <<-SQL
              CREATE TABLE IF NOT EXISTS material (
                  id           INTEGER UNIQUE,
                  category_id  INTEGER,
                  title        VARCHAR,
                  image        VARCHAR,
                  description  VARCHAR,
                  text         TEXT,
                  date         VARCHAR
              );
    SQL
  end


  def get_json(file_name)
    File.open(file_name, 'r').read
  end

  def get_parsed_hash(json)
    Yajl::Parser.new.parse(json)
  end

  def import_one_category(category)
    # если задан параметр only_active_cats и категория неактивна, то не импортируем ни ее, ни вложенные подкатегории
    if options[:only_active_cats] && category['active'] == false
      return false
    end
    begin
      @db.execute('INSERT INTO category (id, name) VALUES (?, ?)', [category['id'], category['name']])
      @count_category_success += 1
      puts "Категория '#{category['name']}' создана"
    rescue Exception => e
      puts "Категория '#{category['name']}' уже существует - #{e.message}"
    end
    # теперь импортируем новости
    category['news'].each do |material|
      import_one_material(material, category['id'])
    end
    category['subcategories'].each {|sub_category| import_one_category(sub_category)}
  end

  def import_one_material(material, category_id)
    # если задан параметр only_active_news и новость неактивна, то не импортируем ее
    if options[:only_active_news] && material['active'] == false
      return false
    end
    begin
      @db.execute(
          'INSERT INTO material (id, category_id, title, image, description, text, date)
           VALUES (?, ?, ?, ?, ?, ?, ?)',
           [material['id'], category_id, material['title'], material['image'], material['description'], material['text'], material['date']]
      )
      @count_news_success += 1
      puts "Новость '#{material['title']}' импортирована"
    rescue Exception => e
      puts "Новость '#{material['title']}' не импортирована - #{e.message}"
      return false
    end
  end

  def show_report
    puts "Были импортированы #{@count_category_success} категорий и #{@count_news_success} новостей"
  end

end


NewsImporter.start(ARGV)



