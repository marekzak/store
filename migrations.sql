-- Základní produkty
CREATE TABLE product (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(120) NOT NULL,
  slug VARCHAR(120) NOT NULL UNIQUE,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_is_active_id (is_active, id)  -- Beru v potaz, že by řazení bylo WHERE is_active ORDER BY id.
  --  Pokud bychom řadili defaultně dle jiného, index ztrácí smysl, ID se indexuje díky primary key
  -- Vlastně všechny ID dávám i do řazení
) ENGINE=InnoDB;

-- Varianty produktu
CREATE TABLE product_variant (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  product_id BIGINT UNSIGNED NOT NULL,
  ean VARCHAR(64) NOT NULL,
  price DECIMAL(12,2) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  combination_hash BINARY(16) NOT NULL, -- hash md5 všech attributů, co varianta má. Pak si z FE vyklikáme MD5 s variantama a nemusíme dělat XY joinů
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pv_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
  UNIQUE KEY uq_pv_comb (product_id, combination_hash),
  KEY idx_product_id_is_active_id (product_id, is_active, id)  -- Zase jsme u složeného indexu. WHERE product_id.. active ... ORDER BY id
) ENGINE=InnoDB;

-- Images
CREATE TABLE product_image (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  product_id BIGINT UNSIGNED NOT NULL,
  -- Nevim, jeslti budeme mít CDN, nedávám tedy URL ani path. Jednoduše zde bude způsob uložení obrázků
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pi_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
  KEY idx_product_id_sort_order (product_id, sort_order)
) ENGINE=InnoDB;

-- Variantní obrázky, myslím že v zadání o tom je zmínka, tak počítám že ano.
CREATE TABLE product_variant_image (
  variant_id BIGINT UNSIGNED NOT NULL,
  image_id BIGINT UNSIGNED NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  PRIMARY KEY (variant_id, image_id),
  CONSTRAINT fk_pvi_variant FOREIGN KEY (variant_id) REFERENCES product_variant(id) ON DELETE CASCADE,
  CONSTRAINT fk_pvi_image   FOREIGN KEY (image_id)   REFERENCES product_image(id)   ON DELETE CASCADE,
  KEY idx_pvi_variant_sort (variant_id, sort_order, image_id)
) ENGINE=InnoDB;

CREATE TABLE attribute (
  id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  code VARCHAR(64) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  is_variant TINYINT(1) NOT NULL DEFAULT 1,
  is_filterable TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE attribute_value (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  attribute_id INT UNSIGNED NOT NULL,
  value VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  settings JSON NULL, -- Nastavení dany vyarianty. Nemusíme mít nějaké unikátní
  CONSTRAINT fk_av_attr FOREIGN KEY (attribute_id) REFERENCES attribute(id) ON DELETE CASCADE,
  UNIQUE KEY uq_av (attribute_id, value),
  KEY idx_attribute_id_slug (attribute_id, slug)
) ENGINE=InnoDB;

CREATE TABLE product_attribute (
  product_id BIGINT UNSIGNED NOT NULL,
  attribute_id INT UNSIGNED NOT NULL,
  PRIMARY KEY (product_id, attribute_id),
  CONSTRAINT fk_pa_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
  CONSTRAINT fk_pa_attr FOREIGN KEY (attribute_id) REFERENCES attribute(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE product_variant_value (
  variant_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  attribute_id INT UNSIGNED NOT NULL,
  attribute_value_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (variant_id, attribute_id),
  CONSTRAINT fk_pvv_variant FOREIGN KEY (variant_id) REFERENCES product_variant(id) ON DELETE CASCADE,
  CONSTRAINT fk_pvv_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
  CONSTRAINT fk_pvv_attr FOREIGN KEY (attribute_id) REFERENCES attribute(id) ON DELETE CASCADE,
  CONSTRAINT fk_pvv_value FOREIGN KEY (attribute_value_id) REFERENCES attribute_value(id) ON DELETE CASCADE,
  KEY idx_pvv_filter (product_id, attribute_id, attribute_value_id, variant_id)
) ENGINE=InnoDB;


--Skladovost, pokud nebudeme řešit nějaké sklady, proudy, bych řešil takto jednoduše a rychle.
CREATE TABLE stock_item (
  variant_id BIGINT UNSIGNED PRIMARY KEY,
  on_hand INT NOT NULL DEFAULT 0 CHECK (on_hand >= 0),
  reserved INT NOT NULL DEFAULT 0 CHECK (reserved >= 0),
  available INT AS (on_hand - reserved) STORED,  -- Generovaný sloupec pro rychlé čtení
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_si_variant FOREIGN KEY (variant_id) REFERENCES product_variant(id) ON DELETE CASCADE,
  KEY idx_si_available (available, variant_id)
) ENGINE=InnoDB;

-- Objednávky:
CREATE TABLE order_item (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  order_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  variant_id BIGINT UNSIGNED NOT NULL,
  qty INT NOT NULL CHECK (qty > 0),
  unit_price DECIMAL(12,2) NOT NULL, -- Cena za kus
  total_price DECIMAL(14,2) NOT NULL, -- unit_price * qty
  product_name VARCHAR(255) NOT NULL, -- fallback pro změnu názvu
  variant_ean VARCHAR(64) NOT NULL, -- ean
  combination_hash BINARY(16) NOT NULL, --Pro rychlejší identifikaci
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_oi_product FOREIGN KEY (product_id) REFERENCES product(id)        ON DELETE RESTRICT,
  CONSTRAINT fk_oi_variant FOREIGN KEY (variant_id) REFERENCES product_variant(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Abych přesně věděl, co objednal, už textově kvůli mazání
CREATE TABLE order_item_attribute (
  order_item_id BIGINT UNSIGNED NOT NULL,
  attribute_code VARCHAR(64) NOT NULL,
  value_slug VARCHAR(255) NOT NULL,)
  value_label VARCHAR(255) NOT NULL,
  PRIMARY KEY (order_item_id, attribute_code),
  CONSTRAINT fk_oia_item FOREIGN KEY (order_item_id) REFERENCES order_item(id) ON DELETE CASCADE
) ENGINE=InnoDB;

--K tasku:
-- Napiš MySQL dotaz a odhadni jeho teoretickou optimální časovou složitost, který se bude používat pro zjištění počtu produktů, které uživatel dostane při zaškrtnutí každého jednotlivého checkboxu ve filtraci - viz obrázek výše s počty produktů v závorkách (vyhledávání na Heureka.cz). Můžeš vypočítat teoretické optimum, případné implementační odlišnosti MySQL nás v tuto chvíli nezajímají.

-- Udělal bych denormalizační tabulku pro product_filter_index, abcyh nemusel v reálném čase vyhledávat přes xy tabulek: https://en.wikipedia.org/wiki/Faceted_search

CREATE TABLE product_filter_index (
  product_id BIGINT UNSIGNED NOT NULL,
  attribute_id INT UNSIGNED NOT NULL,
  attribute_value_id BIGINT UNSIGNED NOT NULL,
  source ENUM('product','variant') NOT NULL,  -- odkud hodnota pochází
  PRIMARY KEY (product_id, attribute_id, attribute_value_id, source),
  KEY idx_pfi_attr (attribute_id, attribute_value_id, product_id),
  CONSTRAINT fk_pfi_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
  CONSTRAINT fk_pfi_attribute FOREIGN KEY (attribute_id) REFERENCES attribute(id) ON DELETE CASCADE,
  CONSTRAINT fk_pfi_attribute_value FOREIGN KEY (attribute_value_id) REFERENCES attribute_value(id) ON DELETE CASCADE
) ENGINE=InnoDB;
