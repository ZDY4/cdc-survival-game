use std::collections::{BTreeMap, BTreeSet};

pub trait WorkspaceDocument {
    type Id: Clone + Ord;

    fn document_id(&self) -> Self::Id;
    fn is_dirty(&self) -> bool;
}

#[derive(Debug, Clone, Default)]
pub struct WorkingDocumentStore<T> {
    documents: BTreeMap<String, T>,
    selected_document_key: Option<String>,
}

impl<T> WorkingDocumentStore<T> {
    pub fn from_documents(documents: BTreeMap<String, T>) -> Self {
        Self {
            documents,
            selected_document_key: None,
        }
    }

    pub fn len(&self) -> usize {
        self.documents.len()
    }

    pub fn is_empty(&self) -> bool {
        self.documents.is_empty()
    }

    pub fn keys(&self) -> impl Iterator<Item = &String> {
        self.documents.keys()
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &T)> {
        self.documents.iter()
    }

    pub fn values(&self) -> impl Iterator<Item = &T> {
        self.documents.values()
    }

    pub fn contains_key(&self, key: &str) -> bool {
        self.documents.contains_key(key)
    }

    pub fn get(&self, key: &str) -> Option<&T> {
        self.documents.get(key)
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut T> {
        self.documents.get_mut(key)
    }

    pub fn insert(&mut self, key: String, document: T) -> Option<T> {
        self.documents.insert(key, document)
    }

    pub fn remove(&mut self, key: &str) -> Option<T> {
        self.documents.remove(key)
    }

    pub fn selected_document_key(&self) -> Option<&String> {
        self.selected_document_key.as_ref()
    }

    pub fn set_selected_document_key(&mut self, key: Option<String>) {
        self.selected_document_key = key;
    }

    pub fn ensure_selection(&mut self) {
        if self
            .selected_document_key
            .as_ref()
            .is_some_and(|key| self.documents.contains_key(key))
        {
            return;
        }
        self.selected_document_key = self.documents.keys().next().cloned();
    }

    pub fn selected_document(&self) -> Option<&T> {
        let key = self.selected_document_key.as_ref()?;
        self.documents.get(key)
    }

    pub fn selected_document_mut(&mut self) -> Option<&mut T> {
        let key = self.selected_document_key.clone()?;
        self.documents.get_mut(&key)
    }
}

impl<T> WorkingDocumentStore<T>
where
    T: WorkspaceDocument,
{
    pub fn current_ids(&self) -> BTreeSet<T::Id> {
        self.documents
            .values()
            .map(WorkspaceDocument::document_id)
            .collect()
    }

    pub fn has_duplicate_ids(&self) -> bool {
        let mut ids = BTreeSet::new();
        self.documents
            .values()
            .any(|document| !ids.insert(document.document_id()))
    }

    pub fn has_dirty_documents(&self) -> bool {
        self.documents.values().any(WorkspaceDocument::is_dirty)
    }

    pub fn dirty_document_keys(&self) -> Vec<String> {
        self.documents
            .iter()
            .filter_map(|(key, document)| document.is_dirty().then_some(key.clone()))
            .collect()
    }
}
