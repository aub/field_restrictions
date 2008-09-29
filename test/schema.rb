ActiveRecord::Schema.define(:version => 20080929014810) do

  create_table "articles", :force => true do |t|
    t.string   "title"
    t.string   "subtitle"
    t.string   "author"
    t.text     "content"
    t.integer  "publication_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "images", :force => true do |t|
    t.string   "title"
    t.integer  "article_id"
    t.integer  "size"
    t.integer  "format"
    t.integer  "mime_type"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "publications", :force => true do |t|
    t.string   "title"
    t.string   "subdomain"
    t.string   "masthead"
    t.integer  "num_authors"
    t.datetime "created_at"
    t.datetime "updated_at"
  end
end
