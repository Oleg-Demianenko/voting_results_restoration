require 'set'

# Предварительно очистим записи от дубликатов по id и ip
def clean_duplicates(input_file, output_file)
  seen_ids = Set.new
  seen_ips = Set.new
  cleaned_lines = []
  File.foreach(input_file) do |line|
    data = line.match(/id: (\d+), time: (.+?), ip: ([\d.]+), candidate: (.+)/)
    if data
      id, ip = data[1], data[3]
      unless seen_ids.include?(id) || seen_ips.include?(ip)
        seen_ids.add(id)
        seen_ips.add(ip)
        cleaned_lines << line
      end
    end
  end
  # Создаём временный файл без дубликатов. Из него потом загрузим данные
  File.open(output_file, "w") { |f| cleaned_lines.each { |line| f.puts(line) } }
  puts "Очистка дубликатов: удалено #{File.foreach(input_file).count - cleaned_lines.size}, осталось #{cleaned_lines.size} записей"
end

# Проверка правильного формата имени-фамилии
def right_name_format?(name)
  words = name.split
  return false if words.size < 2
  # Правильно записанные имя и фамилия, по крайней мере, начинаются с большой буквы
  words.all? { |word| word =~ /\A[A-Z]/ }
end

# Расстояние Левенштейна
def levenshtein_distance(str1, str2)
  n, m = str1.length, str2.length
  current = (0..m).to_a
  (1..n).each do |i|
    previous, current = current, [i] + [0] * m
    (1..m).each do |j|
      cost = str1[i-1] == str2[j-1] ? 0 : 1
      current[j] = [previous[j] + 1, current[j-1] + 1, previous[j-1] + cost].min
    end
  end
  current[m]
end

# ОСНОВНАЯ ПРОГРАММА

# Запишем очищенные от дубликатов данные во временный файл
cleaned_file = "votes_80_cleaned.txt"
clean_duplicates("votes_80.txt", cleaned_file)

# Далее загрузим из него данные о частоте появления имён кандидатов
candidate_frequency = Hash.new(0)
File.foreach(cleaned_file) { |line| candidate_frequency[$1] += 1 if line.match(/candidate: (.+)/) }

# Из первых двухсот отберём верные по формату и составим центры кластеров
centers = candidate_frequency.sort_by { |_, count| -count }
                             .first(200)
                             .select { |name, _| right_name_format?(name) }
                             .map(&:first)

puts "Выбрано центров кластеров: #{centers.size}"
puts "Уникальных кандидатов: #{candidate_frequency.size}"

# Проведём кластеризацию
clusters = []
# Будем записывать центры кластеров, чтобы не включить их в другие кластеры
assigned = Set.new
all_names = candidate_frequency.keys

puts "\nСоздание кластеров:"
centers.each do |center|
  cluster = [center]
  assigned.add(center)
  all_names.each do |candidate|
    next if candidate == center || centers.include?(candidate)
    # При разнице более двух символов или более двух изменений имя не считается похожим
    if (center.length - candidate.length).abs <= 2 && levenshtein_distance(center, candidate) <= 2
      cluster << candidate
      # Кандидатов тоже учитываем, чтобы не сравнивать каждого
      assigned.add(candidate)
    end
  end

  clusters << cluster
  # За одно будем выводить информацию о том, сколько похожих имён объединили в каждый кластер
  puts "#{clusters.size}: #{center.ljust(20)} (+#{cluster.size - 1} похожих)"
end

# Сделаем по отдельному кластеру для оставшихся кандидатов
remaining = all_names - assigned.to_a
# Если они конечно остались
if remaining.any?
  puts "\nКластеры для оставшихся кандидатов:"
  remaining.each do |candidate|
    clusters << [candidate]
    puts "#{clusters.size}: #{candidate}"
  end
end

puts "\nИтого:"
puts "Всего кластеров: #{clusters.size}"
puts "Распределено кандидатов: #{assigned.size}"
puts "Отдельных кандидатов: #{remaining.size}"
puts "_" * 40

# Подсчитаем голоса для каждого кластера
votes_by_cluster = Hash.new(0)
total_votes = 0
# Для этого пройдёмся по записям
File.foreach(cleaned_file) do |line|
  if line.match(/candidate: (.+)/)
    candidate = $1
    total_votes += 1
    clusters.each do |cluster|
      if cluster.include?(candidate)
        votes_by_cluster[cluster[0]] += 1
        break
      end
    end
  end
end

# Выводим получившиеся результаты голосования
puts "\nРезультаты голосования:"
# Расположим в порядке убывания
votes_by_cluster.sort_by { |_, votes| -votes }.each do |candidate, votes|
  percentage = (votes.to_f / total_votes * 100).round(2)
  puts "#{candidate.ljust(20)} : #{votes.to_s.ljust(4)} голосов (#{percentage}%)"
end

# И убедимся, что все голоса были учтены и распределены по кластерам (кандидатам)
puts "_" * 40
puts "Всего голосов: #{total_votes}"
puts "Покрытие кластеризации: #{(votes_by_cluster.values.sum.to_f / total_votes * 100).round(2)}%"

# Удалим временный файл
File.delete(cleaned_file) if File.exist?(cleaned_file)