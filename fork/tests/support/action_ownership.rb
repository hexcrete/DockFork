# Include the production ownership model in inert source-extracted Swift fixtures.
def with_action_ownership(source)
  return source unless source.include?('WindowActionRequest')
  return source if source.include?('final class WindowActionRequest:')
  catalog = File.read(File.expand_path('../../../DockDoor/Utilities/Window Management/WindowActionCatalog.swift', __dir__))
  model = catalog[catalog.index('final class WindowActionRequest:')...catalog.index('enum PreviewBatchTogglePolicy {')]
  model + "\n" + source
end
